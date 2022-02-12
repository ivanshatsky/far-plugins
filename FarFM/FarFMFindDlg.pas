{$I Defines.inc}

unit FarFMFindDlg;

interface

  uses
    Windows,
    MSXML,

    MixTypes,
    MixUtils,
    MixStrings,

    Far_API,
    FarCtrl,
    FarDlg,
    FarGrid,

    FarFMCtrl,
    FarFmCalls;


  function FindDlg(const APrompt :TString; var AName :TString) :Boolean;
  function FindUrlDlg(const AKey, AOldURL :TString; var AURL :TString) :Boolean;

{******************************************************************************}
{******************************} implementation {******************************}
{******************************************************************************}

  uses
    MixDebug;


  procedure TrimAndFilter(var Arr :TStringArray2);
  var
    I, J, K :Integer;
    vEmpty :Boolean;
  begin
    K := 0;
    for I := 0 to length(Arr) - 1 do begin
      vEmpty := True;
      for J := 0 to length(Arr[I]) - 1 do begin
        Arr[I, J] := Trim(Arr[I, J]);
        if Arr[I, J] <> '' then
          vEmpty := False;
      end;
      if I > K then
        Arr[K] := Arr[I];
      if not vEmpty then
        Inc(K);
    end;
    if K < length(Arr) then
      SetLength(Arr, K);
  end;


  var
    cDlgTitle :array[1..3] of TMessages = (
      strFindArtist,
      strFindUser,
      strFindTrackURL
    );

    cHistName :array[1..3] of PTChar = (
      'FarFM.Find',
      'FarFM.FindUser',
      'FarFM.Track'
    );

    cFindWhats :array[0..2] of TMessages = (
      strArtists,
      strAlbums,
      strTracks
    );

    cCol2Title :array[0..3] of TMessages = (
      strListeners,
      strAlbum,
      strTrack,
      strTrack
    );

    cCol2Align :array[0..3] of TAlignment = (
      taRightJustify,
      taLeftJustify,
      taLeftJustify,
      taLeftJustify
    );


  const
    cDlgDefWidth  = 60;
    cDlgMinWidth  = 40;
    cDlgMinHeight = 12;

    cTypeDX   = 11;

    IdFrame   = 0;
    IdPrompt  = 1;
    IdEdit    = 2;
    IdPrompt2 = 3;
    IdEdit2   = 4;
    IdGrid    = 5;
    IdDel     = 6;
    IdOk      = 7;
    IdCancel  = 8;


  type
    TFindDlg = class(TFarDialog)
    public
      constructor CreateEx(AMode :Integer);
      destructor Destroy; override;

    protected
      procedure Prepare; override;
      procedure InitDialog; override;
      function CloseDialog(ItemID :Integer) :Boolean; override;
      function KeyDown(AID :Integer; AKey :Integer) :Boolean; override;
      function DialogHandler(Msg :Integer; Param1 :Integer; Param2 :TIntPtr) :TIntPtr; override;
      procedure ErrorHandler(E :Exception); override;

    private
      FMode     :Integer; { FMode: 1 - поиск исполнителей, 2 - поиск пользователей, 3 - поиск URL }


      FPrompt   :TString;
      FRes      :TString;
      FURL      :TString;

      FChanged  :Boolean;

      FGrid     :TFarGrid;
      FMaxWidth :Integer;

      FList     :TStringArray2;
      FListMode :Integer;

      procedure RunFind;
      procedure ReinitGrid;
      procedure ResizeDialog;

      function GridGetDlgText(ASender :TFarGrid; ACol, ARow :Integer) :TString;
    end;


  constructor TFindDlg.CreateEx(AMode :Integer);
  begin
    FMode := AMode;
    Create;
  end;


  destructor TFindDlg.Destroy; {override;}
  begin
    FreeObj(FGrid);
//  UnregisterHints;
    inherited Destroy;
  end;


  procedure TFindDlg.Prepare; {override;}
  var
    X1 :Integer;
  begin
//  FHelpTopic := 'Find';
    FGUID := cFindDlgID;
    FWidth := cDlgDefWidth;
    FHeight := cDlgMinHeight;
    X1 := FWidth-5-cTypeDX;
    FDialog := CreateDialog(
      [
        NewItemApi(DI_DoubleBox,   3,  1, FWidth-6, FHeight-2, 0, GetMsg(cDlgTitle[FMode])),

        NewItemApi(DI_Text,        5,  2, X1-7, -1, 0, GetMsg(strFindTextPrompt) ),
        NewItemApi(DI_Edit,        5,  3, X1-7, -1, DIF_HISTORY, '', cHistName[FMode] ),

        NewItemApi(DI_Text,        X1, 2, cTypeDX, -1, 0, GetMsg(strFindWherePrompt) ),
        NewItemApi(DI_ComboBox,    X1, 3, cTypeDX, -1, DIF_DROPDOWNLIST, ''),

        NewItemApi(DI_USERCONTROL, 5,  5, FWidth-10, FHeight-9, 0, '' ),

        NewItemApi(DI_Text,        0, FHeight-4, -1, -1, DIF_SEPARATOR, ''),
        NewItemApi(DI_DefButton,   0, FHeight-3, -1, -1, DIF_CENTERGROUP, GetMsg(strOk)),
        NewItemApi(DI_Button,      0, FHeight-3, -1, -1, DIF_CENTERGROUP, GetMsg(strCancel))
      ], @FItemCount
    );

    FGrid := TFarGrid.CreateEx(Self, IdGrid);
    FGrid.Options := [goRowSelect {, goFollowMouse} {,goWheelMovePos} ];
    FGrid.NormColor := FarGetColor(COL_DIALOGLISTTEXT);
    FGrid.SelColor := FarGetColor(COL_DIALOGLISTSELECTEDTEXT);
    FGrid.TitleColor := FarGetColor(COL_DIALOGLISTHIGHLIGHT);

//  FGrid.NormColor := FarGetColor(COL_DIALOGEDIT);
//  FGrid.SelColor := FarGetColor(COL_DIALOGEDITSELECTED);

//  FGrid.OnCellClick := GridCellClick;
    FGrid.OnGetCellText := GridGetDlgText;
  end;


  procedure TFindDlg.InitDialog; {override;}
  begin
    SendMsg(DM_SETMOUSEEVENTNOTIFY, 1, 0);

    if FMode = 1 then begin
      SetListItems(IdEdit2, [
        GetMsgStr(cFindWhats[0]),
        GetMsgStr(cFindWhats[1]),
        GetMsgStr(cFindWhats[2])
      ]);
      SetListIndex(IdEdit2, 0);
      SetText(IdEdit2, GetMsgStr(cFindWhats[0]));
    end else
    begin
      SendMsg(DM_ShowItem, IdPrompt2, 0);
      SendMsg(DM_ShowItem, IdEdit2, 0);
    end;

    if FMode <> 3 then begin
      SetEnabled(IdOk, False);
      FChanged := True;
    end else
    begin
      SetText(IdEdit, FRes);
      FChanged := True;
    end;

    ReinitGrid;
  end;


  function TFindDlg.CloseDialog(ItemID :Integer) :Boolean; {virtual;}
  begin
    if (ItemID <> -1) and (ItemID <> IdCancel) then begin
      if FChanged then begin
        RunFind;
        Result := False;
      end else
      begin
        if FMode <> 3 then
          FRes := FList[FGrid.CurRow, 0]
        else
          FRes := FList[FGrid.CurRow, 2];
        Result := True;
      end;
    end else
      Result := True;
  end;


 {-----------------------------------------------------------------------------}

  function TFindDlg.GridGetDlgText(ASender :TFarGrid; ACol, ARow :Integer) :TString;
  begin
    if ARow < length(FList) then begin
      Result := FList[ARow, ACol];

      if (FMode = 3) and (ACol = 0) then begin
        Result := ' ' + Result;
        if (length(FList[ARow]) >= 3) and StrEqual(FURL, FList[ARow, 2]) then
          Result[1] := '*'
      end;
    end;
  end;


  procedure TFindDlg.ReinitGrid;
  var
    I, vMaxLen1, vMaxLen2, vMaxLen3 :Integer;
    vShowCol3 :Boolean;
  begin
    vShowCol3 := (FListMode = 3) and opt_ShowURL;

    FMaxWidth := 0;
    vMaxLen1 := 0; vMaxLen2 := 0; vMaxLen3 := 0;
    for I := 0 to length(FList) - 1 do begin
      vMaxLen1 := IntMax(vMaxLen1, Length(FList[I, 0]));
      vMaxLen2 := IntMax(vMaxLen2, Length(FList[I, 1]));
      if vShowCol3 and (Length(FList[I]) >= 3) then
        vMaxLen3 := IntMax(vMaxLen3, Length(FList[I, 2]));
    end;

    Inc(vMaxLen1, 2);
    Inc(vMaxLen2, 2);
    if vShowCol3 then
      Inc(vMaxLen3, 2);

    if vMaxLen1 + vMaxLen2 + vMaxLen3 + 5{4+1} < cDlgDefWidth then
      vMaxLen1 := cDlgDefWidth - (vMaxLen2 + vMaxLen3 + 5);

    FGrid.ResetSize;
    FGrid.Columns.FreeAll;
    FGrid.Columns.Add( TColumnFormat.CreateEx('', GetMsgStr(strArtist), vMaxLen1, taLeftJustify, [coColMargin], 1) );
    FGrid.Columns.Add( TColumnFormat.CreateEx('', GetMsgStr(cCol2Title[FListMode]), vMaxLen2, cCol2Align[FListMode], [coColMargin], 2) );
    if vShowCol3 then
      FGrid.Columns.Add( TColumnFormat.CreateEx('', 'URL', vMaxLen3, taLeftJustify, [coColMargin], 3) );

    FGrid.ReduceColumns( IntMax(FarGetWindowSize.CX - 4, cDlgMinWidth) - 6 - 4 - (FGrid.Columns.Count-1) );
    FMaxWidth := FGrid.CalcGridColumnsWidth + 4;

    if length(FList) > 0 then
      FGrid.Options := FGrid.Options + [goShowTitle]
    else
      FGrid.Options := FGrid.Options - [goShowTitle];

    FGrid.RowCount := length(FList);

    if FChanged then
      SetText(IdOk, GetMsgStr(strFindBut))
    else begin
      SetText(IdOk, GetMsgStr(strAddBut));
      SetEnabled(IdOk, FGrid.RowCount > 0);
    end;

    SendMsg(DM_ENABLEREDRAW, 0, 0);
    try
      ResizeDialog;
    finally
      SendMsg(DM_ENABLEREDRAW, 1, 0);
    end;
  end;


  procedure TFindDlg.ResizeDialog;
  var
    vWidth, vHeight, vTypeDX :Integer;
    vRect, vRect1 :TSmallRect;
    vSize :TSize;
  begin
    vSize := FarGetWindowSize;

    vWidth := IntMax(FMaxWidth + 6, cDlgDefWidth);
    if vWidth > vSize.CX - 4 then
      vWidth := vSize.CX - 4;
    vWidth := IntMax(vWidth, cDlgMinWidth);

    vHeight := FGrid.RowCount + 9;
    if goShowTitle in FGrid.Options then
      Inc(vHeight);
    vHeight := IntMax(vHeight, cDlgMinHeight);
    if vHeight > vSize.CY - 2 then
      vHeight := vSize.CY - 2;
    vHeight := IntMax(vHeight, cDlgMinHeight);

    vRect := SBounds(3, 1, vWidth - 7, vHeight - 3);
    SendMsg(DM_SETITEMPOSITION, IdFrame, @vRect);

    RectGrow(vRect, -1, -1);

    vTypeDX := IntIf(FMode = 1, cTypeDX, -1);
    vRect1 := SRect(vRect.Left + 1, vRect.Top, vRect.Right - vTypeDX - 3, vRect.Top + 1);
    SendMsg(DM_SETITEMPOSITION, IdPrompt, @vRect1);
    RectMove(vRect1, 0, 1);
    SendMsg(DM_SETITEMPOSITION, IdEdit, @vRect1);

    if FMode = 1 then begin
      vRect1 := SRect(vRect.Right - vTypeDX, vRect.Top, vRect.Right - 1, vRect.Top + 1);
      SendMsg(DM_SETITEMPOSITION, IdPrompt2, @vRect1);
      RectMove(vRect1, 0, 1);
      SendMsg(DM_SETITEMPOSITION, IdEdit2, @vRect1);
    end;

    vRect1 := SRect(vRect.Left + 1, vRect.Top + 3, vRect.Right - 1, vRect.Bottom - 2);
    SendMsg(DM_SETITEMPOSITION, IdGrid, @vRect1);
    FGrid.UpdateSize(vRect1.Left, vRect1.Top, vRect1.Right - vRect1.Left + 1, vRect1.Bottom - vRect1.Top + 1);

    vRect1 := vRect;
    vRect1.Top := vRect1.Bottom - 1;
    SendMsg(DM_SETITEMPOSITION, IdDel, @vRect1);

    RectMove(vRect1, 0, 1);
    SendMsg(DM_SETITEMPOSITION, IdOk, @vRect1);
    SendMsg(DM_SETITEMPOSITION, IdCancel, @vRect1);

    SetDlgPos(-1, -1, vWidth, vHeight);
  end;


 {-----------------------------------------------------------------------------}

  procedure TFindDlg.RunFind;
  var
    vStr :TString;
    vDoc :IXMLDOMDocument;
  begin
    vStr := Trim(GetText(IdEdit));
    if vStr = '' then
      Exit;

    if FMode = 1 then begin

      FListMode := SendMsg(DM_LISTGETCURPOS, IdEdit2, 0);
      if FListMode = 0 then begin
        vDoc := LastFMCall('artist.search', ['artist', vStr]);
        FList := XMLParseArray(vDoc, 'lfm/results/artistmatches/artist', ['name', 'listeners']);
      end else
      if FListMode = 1 then begin
        vDoc := LastFMCall('album.search', ['album', vStr]);
        FList := XMLParseArray(vDoc, 'lfm/results/albummatches/album', ['artist', 'name']);
      end else
      if FListMode = 2 then begin
        vDoc := LastFMCall('track.search', ['track', vStr]);
        FList := XMLParseArray(vDoc, 'lfm/results/trackmatches/track', ['artist', 'name']);
      end else
        Sorry;

    end else
    if FMode = 2 then begin
      {???}
      FListMode := -1;
      vDoc := LastFMCall('user.search', ['user', vStr]);
    end else
    if FMode = 3 then begin
      FListMode := 3;
      vDoc := VkCall('audio.search', ['q', vStr {, 'count', Int2Str(cTryVariants)} ]);
      FList := XMLParseArray(vDoc, '/response/audio', ['artist', 'title', 'url']);
    end else
      Wrong;
      
    TrimAndFilter(FList);

    FChanged := False;
    FGrid.GotoLocation(0, 0, lmScroll);
    ReinitGrid;
  end;


 {-----------------------------------------------------------------------------}

  function TFindDlg.KeyDown(AID :Integer; AKey :Integer) :Boolean; {override;}

    procedure LocToggleOption(var AOption :Boolean);
    begin
      AOption := not AOption;
//    PluginConfig(True);
      ReInitGrid;
    end;

  begin
    Result := True;
    case AKey of
      KEY_CTRL3:
        LocToggleOption(opt_ShowURL);

      KEY_UP, KEY_DOWN, KEY_PGUP, KEY_PGDN, KEY_CTRLPGUP, KEY_CTRLPGDN:
        if SendMsg(DM_GETFOCUS, 0, 0) = IdEdit then
          FGrid.KeyDown(AKey)
        else
          Result := inherited KeyDown(AID, AKey);
     else
       Result := inherited KeyDown(AID, AKey);
    end;
  end;


  function TFindDlg.DialogHandler(Msg :Integer; Param1 :Integer; Param2 :TIntPtr) :TIntPtr; {override;}
  begin
    Result := 1;
    case Msg of
      DN_RESIZECONSOLE: begin
        ReInitGrid;
        FGrid.GotoLocation(FGrid.CurCol, FGrid.CurRow, lmScroll);
      end;

      DN_EDITCHANGE:
        if Param1 = IdEdit then begin
          if not FChanged then begin
            FChanged := True;
            FList := nil;
            ReinitGrid;
          end;
          SetEnabled(IdOk, not StrIsEmpty(GetText(IdEdit)));
        end else
        if Param1 = IdEdit2 then begin
          if  not FChanged then
            SetText(IdEdit, '');
        end;

    else
      Result := inherited DialogHandler(Msg, Param1, Param2);
    end;
  end;


  procedure TFindDlg.ErrorHandler(E :Exception); {override;}
  begin
    if not (E is EAbort) then
      ShowMessage(cPluginName, E.Message, FMSG_WARNING or FMSG_MB_OK or FMSG_LEFTALIGN);
  end;

 {-----------------------------------------------------------------------------}
 {                                                                             }
 {-----------------------------------------------------------------------------}

  function FindDlg(const APrompt :TString; var AName :TString) :Boolean;
  var
    vDlg :TFindDlg;
    vRes :Integer;
  begin
    Result := False;
    vDlg := TFindDlg.CreateEx(1);
    try
      vDlg.FPrompt := APrompt;
      vDlg.FRes := AName;

      vRes := vDlg.Run;
      if (vRes = -1) or (vRes = IdCancel) then
        Exit;

      AName := vDlg.FRes;
      Result := AName <> '';
    finally
      FreeObj(vDlg);
    end;
  end;


  function FindUrlDlg(const AKey, AOldURL :TString; var AURL :TString) :Boolean;
  var
    vDlg :TFindDlg;
    vRes :Integer;
  begin
    Result := False;
    vDlg := TFindDlg.CreateEx(3);
    try
      vDlg.FRes := AKey;
      vDlg.FURL := AOldURL;

      vRes := vDlg.Run;
      if (vRes = -1) or (vRes = IdCancel) then
        Exit;

      AURL := vDlg.FRes;
      Result := AURL <> '';
    finally
      FreeObj(vDlg);
    end;
  end;

end.

