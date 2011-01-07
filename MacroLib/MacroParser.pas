{$I Defines.inc}

unit MacroParser;

{******************************************************************************}
{* (c) 2010 Max Rusov                                                         *}
{*                                                                            *}
{* MacroLib                                                                   *}
{******************************************************************************}

interface

  uses
    Windows,

    MixTypes,
    MixUtils,
    MixStrings,
    MixClasses,

    PluginW,
    FarCtrl;


  var
    ParserResBase :Integer;


  type
    TMacroParser = class;

    TLexType = (
      lexError,
      lexWord,
      lexString,
      lexNumber,
      lexSymbol,
      lexStartSeq,
      lexEOF
    );

    TParseError = (
      errFatalError,
      errKeywordExpected,
      errUnknownKeyword,
      errExpectMacroBody,
      errExpectEqualSign,
      errExpectValue,
      errExceptString,
      errUnclosedString,
      errBadNumber,
      errBadHotkey,
      errBadMacroarea,
      errUnexpectedEOF,
      errBadMacroSequence,
      wrnUnknownParam
    );

    TIntArray = array of Integer;

    TMacroOption =
    (
      moDisableOutput,
      moSendToPlugins,
      moRunOnRelease,
      moEatOnRun
    );
    TMacroOptions = set of TMacroOption;

    TMacroRec = record
      Name     :TString;
      Descr    :TString;
      Bind     :TIntArray;
      Area     :DWORD;
      Cond     :DWORD;
      Where    :TString;
      Text     :TString;
      Options  :TMacroOptions;
      Row, Col :Integer;  { �������� � ��������� ������ }
    end;

    EParseError = class(Exception)
    public
      FRow :Integer;
      FCol :Integer;

      constructor CreateEx(ACode :TParseError; ARow, ACol :Integer);
    end;

    TOnAddEvent = procedure(Sender :TMacroParser; const ARec :TMacroRec) of object;
    TOnError = procedure(Sender :TMacroParser; ACode :Integer; const AMessage :TString; const AFileName :TString; ARow, ACol :Integer) of object;

    TMacroParser = class(TBasis)
    public
      constructor Create; override;
      destructor Destroy; override;

      function Parse(AText :PTChar) :boolean;
      function ParseFile(const AFileName :TString) :boolean;

      procedure ShowSequenceError;

    private
      FFileName  :TString;
      FSafe      :Boolean;
      FCheckBody :Boolean;

      FMacro     :TMacroRec;
      FBuf       :PTChar;
      FRow       :Integer;
      FBeg       :PTChar;
      FCur       :PTChar;
      FLen       :Integer;
      FSize      :Integer;

      FSeqRow    :Integer;
      FSeqCol    :Integer;

      FOnAdd     :TOnAddEvent;
      FOnError   :TOnError;

      procedure Error(ACode :TParseError; ARow :Integer = 0; ACol :Integer = 0);
      procedure Warning(ACode :TParseError);

      procedure ParseMacroSequence(var APtr :PTChar);
      procedure CheckMacroSequence(const AText :TString; ASilence :Boolean);
      function GetLex(var APtr :PTChar; var AParam :PTChar; var ALen :Integer) :TLexType;
      procedure SkipSpacesAndComments(var APtr :PTChar);
      procedure SkipLineComment(var APtr :PTChar);
      procedure SkipMultilineComment(var APtr :PTChar);
      procedure SkipCRLF(var APtr :PTChar);
      procedure ParseBindStr(APtr :PTChar; var ARes :TIntArray);
      procedure ParseAreaStr(APtr :PTChar; var ARes :DWORD);
      procedure AddBuf(APtr :PTChar; ALen :Integer);
      procedure AddChars(AChr :TChar; ALen :Integer);
      procedure SetBufSize(ASize :Integer);
      function GetStrValue :TString;
      function GetIntValue :Integer;
      procedure NewMacro;
      procedure SetMacroParam(AParam :Integer; ALex :TLexType);
      procedure AddMacro;
      procedure ShowError(E :EParseError);

    public
      property FileName :TString read FFileName;
      property Safe :Boolean read FSafe write FSafe;
      property CheckBody :Boolean read FCheckBody write FCheckBody;
      property OnAdd :TOnAddEvent read FOnAdd write FOnAdd;
      property OnError :TOnError read FOnError write FOnError;
    end;

  function FarAreaToName(Area :Integer) :TString;

{******************************************************************************}
{******************************} implementation {******************************}
{******************************************************************************}

  uses
    MixDebug;

  const
    cLineComment1 = ';;';
    cLineComment2 = '//';

    cInLineCommentBeg = '/*';
    cInLineCommentEnd = '*/';

  const
    kwMacro    = 1;  
    kwName     = 2;  
    kwDescr    = 3;  
    kwBind     = 4;  
    kwWhere    = 5;  
    kwArea     = 6;  
    kwCond     = 7;  
    kwSilence  = 8;  
    kwSendPlug = 9;
    kwRunOnRelease = 10;
    kwEatOnRun = 11;



  function MatchStr(APtr, AMatch :PTChar) :Boolean;
  begin
    while (AMatch^ <> #0) and (APtr^ = AMatch^) do begin
      Inc(AMatch);
      Inc(APtr);
    end;
    Result := AMatch^ = #0;
  end;


  function CanExtractNextWord(var APtr :PTChar; ABuf :PTChar; AMaxLen :Integer) :Boolean;
  var
    vBeg :PTChar;
  begin
    Result := False;
    while ChrInSet(APtr^, [' ', ',', ';', charTab]) do
      Inc(APtr);
    if APtr^ <> #0 then begin
      vBeg := APtr;
      while (APtr^ <> #0) and not ChrInSet(APtr^, [' ', ',', ';', charTab]) do
        Inc(APtr);
      StrLCopy(ABuf, vBeg, IntMin(AMaxLen, APtr - vBeg));
      Result := True;
    end;
  end;


 {-----------------------------------------------------------------------------}
 {                                                                             }
 {-----------------------------------------------------------------------------}

  constructor EParseError.CreateEx(ACode :TParseError; ARow, ACol :Integer);
  begin
    CreateHelp('', byte(ACode));
    FRow := ARow;
    FCol := ACol;
  end;


 {-----------------------------------------------------------------------------}
 { TKeywords                                                                   }
 {-----------------------------------------------------------------------------}

  type
    TKeyword = class(TNamedObject)
    public
      Key :Integer;
      function CompareKey(Key :Pointer; Context :TIntPtr) :Integer; override;
    end;

    TKeywordsList = class(TObjList)
    public
      procedure Add(const AKeyword :TString; AKey :Integer);
      function GetKeyword(APtr :PTChar; ALen :Integer) :Integer;
    end;


  function TKeyword.CompareKey(Key :Pointer; Context :TIntPtr) :Integer; {override;}
  begin
    if Context <> 0 then
      Result := UpCompareBuf(PTChar(FName)^, Key^, length(FName), Context)
    else
      Result := inherited CompareKey(Key, Context);
  end;


  procedure TKeywordsList.Add(const AKeyword :TString; AKey :Integer);
  var
    vKeyword :TKeyword;
  begin
    vKeyword := TKeyword.Create;
    vKeyword.Name := AKeyword;
    vKeyword.Key := AKey;
    AddSorted(vKeyword, 0, dupError);
  end;


  function TKeywordsList.GetKeyword(APtr :PTChar; ALen :Integer) :Integer;
  var
    vIndex :Integer;
  begin
    if FindKey(APtr, ALen, [foBinary], vIndex) then
      Result := TKeyword(Items[vIndex]).Key
    else
      Result := -1;
  end;


  var
    Keywords :TKeywordsList;
    KeyAreas :TKeywordsList;

  procedure InitKeywords;
  begin
    if Keywords <> nil then
      Exit;

    Keywords := TKeywordsList.Create;
    with Keywords do begin
      Add('MACRO', kwMacro); Add('$MACRO',kwMacro);
      Add('NAME',  kwName);
      Add('DESCR', kwDescr); Add('DESCRIPTION', kwDescr);
      Add('BIND',  kwBind);  Add('KEY',kwBind); Add('KEYS',kwBind); Add('HOTKEY',kwBind); Add('HOTKEYS',kwBind);
      Add('WHERE', kwWhere); Add('IF', kwWhere);
      Add('AREA',  kwArea);  Add('AREAS',  kwArea);
      Add('COND',  kwCond);  Add('CONDITION', kwCond);

      Add('DISABLEOUTPUT', kwSilence);
      Add('SENDTOPLUGIN',  kwSendPlug);
      Add('RUNONRELEASE',  kwRunOnRelease);
      Add('EATONRUN',      kwEatOnRun);
    end;

    KeyAreas := TKeywordsList.Create;
    with KeyAreas do begin
      Add('Shell',          MACROAREA_SHELL);
      Add('Viewer',         MACROAREA_VIEWER);
      Add('Editor',         MACROAREA_EDITOR);
      Add('Dialog',         MACROAREA_DIALOG);
      Add('Search',         MACROAREA_SEARCH);
      Add('Disks',          MACROAREA_DISKS);
      Add('MainMenu',       MACROAREA_MAINMENU);
      Add('Menu',           MACROAREA_MENU);
      Add('Help',           MACROAREA_HELP);
      Add('InfoPanel',      MACROAREA_INFOPANEL);
      Add('QViewPanel',     MACROAREA_QVIEWPANEL);
      Add('TreePanel',      MACROAREA_TREEPANEL);
      Add('FindFolder',     MACROAREA_FINDFOLDER);
      Add('UserMenu',       MACROAREA_USERMENU);
      Add('AutoCompletion', MACROAREA_AUTOCOMPLETION);
    end;
  end;


  function FarAreaToName(Area :Integer) :TString;
  var
    I :Integer;
  begin
    InitKeywords;
    for I := 0 to KeyAreas.Count - 1 do
      with TKeyword(KeyAreas[I]) do
        if Key = Area then begin
          Result := Name;
          Exit;
        end;
    Result := '';
  end;


 {-----------------------------------------------------------------------------}
 { TMacroParser                                                                }
 {-----------------------------------------------------------------------------}

  constructor TMacroParser.Create;
  begin
    inherited Create;
    InitKeywords;
  end;


  destructor TMacroParser.Destroy; {override;}
  begin
    MemFree(FBuf);
    inherited Destroy;
  end;


  procedure TMacroParser.Error(ACode :TParseError; ARow :Integer = 0; ACol :Integer = 0);
  begin
    raise EParseError.CreateEx(ACode, ARow, ACol);
  end;


  procedure TMacroParser.Warning(ACode :TParseError);
  begin
    if FSafe then
      {}
    else
      raise EParseError.CreateHelp('', Byte(ACode));
  end;


  function TMacroParser.ParseFile(const AFileName :TString) :boolean;
  var
    vText :TString;
  begin
    FFileName := AFileName;

    { ������ ���� }
    vText := StrFromFile(AFileName);

    Result := Parse(PTChar(vText));
  end;


  function TMacroParser.Parse(AText :PTChar) :boolean;
  var
    vPtr, vParam, vParam1 :PTChar;
    vLen, vLen1, vKey :Integer;
    vLex :TLexType;
    vWasBody :Boolean;
  begin
    Result := False;
    try
      FRow := 0;
      FBeg := AText;
      FCur := FBeg;
      vPtr := AText;
      while vPtr^ <> #0 do begin
        vLex := GetLex(vPtr, vParam, vLen);
        if vLex = lexEOF then
          Break;
        if vLex <> lexWord then
          Error(errKeywordExpected);

        vKey := Keywords.GetKeyword(vParam, vLen);
        if vKey = kwMacro then begin
          { ������ ������� }
          NewMacro;
          vWasBody := False;
          while vPtr^ <> #0 do begin
            vLex := GetLex(vPtr, vParam, vLen);
            if vLex = lexWord then begin

              vKey := Keywords.GetKeyword(vParam, vLen);
              if vKey = -1 then
                Warning(wrnUnknownParam);

              vLex := GetLex(vPtr, vParam1, vLen1);
              if (vLex = lexSymbol) and (vParam1^ = '=') then begin

                vLex := GetLex(vPtr, vParam1, vLen1);
                if (vLex <> lexString) and (vLex <> lexNumber) then
                  Error(errExpectValue);

                SetMacroParam(vKey, vLex);

                FCur := vPtr;

              end else
                Error(errExpectEqualSign);

            end else
            if (vLex = lexSymbol) and MatchStr(vParam, '{{') then begin

              Inc(vPtr);
              ParseMacroSequence(vPtr);

              FMacro.Text := GetStrValue;
              vWasBody := True;

              if FCheckBody then
                CheckMacroSequence(PTChar(FMacro.Text), True);

              Break;

            end else
              Error(errExpectMacroBody);
          end;

          if not vWasBody then
            Error(errExpectMacroBody);

          AddMacro;

        end else
          Error(errUnknownKeyword);
      end;

      Result := True;

    except
      on E :EParseError do
        ShowError(E);
      else
        raise;
    end;
  end;


  procedure TMacroParser.ParseMacroSequence(var APtr :PTChar);
  var
    vRow :Integer;
    vPos :PTChar;
  begin
    FLen := 0;
    SkipSpacesAndComments(APtr);
    FSeqRow := FRow;
    FSeqCol := APtr - FBeg;
    while (APtr^ <> #0) and not MatchStr(APtr, '}}') do begin
      if (APtr^ = charCR) or (APtr^ = charLF) then begin
        if (FLen > 0) and (FBuf[FLen - 1] <> #13) then
          AddBuf(#13, 1)
        else
          AddBuf(' '#13, 2);
        SkipCRLF(APtr);
      end else
      if MatchStr(APtr, cLineComment1) or MatchStr(APtr, cLineComment2) then
        { ������������ ����������� }
        SkipLineComment(APtr)
      else
      if MatchStr(APtr, cInLineCommentBeg) then begin
        { ������������� ����������� }
        vRow := FRow;
        vPos := APtr;

        SkipMultilineComment(APtr);

        if FRow > vRow then begin
          while vRow < FRow do begin
            AddBuf(' '#13, 2);
            Inc(vRow);
          end;
          vPos := FBeg;
        end;

        if APtr > vPos then
          AddChars(' ', APtr - vPos)

      end else
      if APtr^ = '"' then begin
        {��������� ��������� ���������}
        vPos := APtr;
        Inc(APtr);
        while (APtr^ <> #0) and (APtr^ <> charCR) and (APtr^ <> charLF) and (APtr^ <> '"') do begin
          if APtr^ = '\' then
            Inc(APtr, 2)
          else
            Inc(APtr);
        end;
        if APtr^ <> '"' then
          Error(errUnclosedString);
        Inc(APtr);
        AddBuf(vPos, APtr - vPos);
      end else
      begin
        AddBuf(APtr, 1);
        Inc(APtr);
      end;
    end;
    if APtr^ = #0 then
      Error(errUnexpectedEOF);
    Inc(APtr, 2);

    while (FLen > 0) and ChrInSet(FBuf[FLen - 1], [charCR, ' ']) do
      Dec(FLen);
  end;


  procedure TMacroParser.ShowSequenceError;
  begin
    CheckMacroSequence(PTChar(FMacro.Text), False);
  end;


  procedure TMacroParser.CheckMacroSequence(const AText :TString; ASilence :Boolean);
  var
    vMacro :TActlKeyMacro;
  begin
//  TraceF('Sequence=%s', [AText]);
    vMacro.Command := MCMD_CHECKMACRO;
    vMacro.Param.PlainText.SequenceText := PTChar(AText);
    vMacro.Param.PlainText.Flags := IntIf(ASilence, KSFLAGS_SILENTCHECK, 0);
    FARAPI.AdvControl(hModule, ACTL_KEYMACRO, @vMacro);
    if ASilence and (vMacro.Param.MacroResult.ErrCode <> MPEC_SUCCESS) then
      with vMacro.Param.MacroResult do
        Error(errBadMacroSequence, FSeqRow + ErrPos.Y, ErrPos.X + IntIf(ErrPos.Y = 0, FSeqCol, 0));
  end;


  function TMacroParser.GetLex(var APtr :PTChar; var AParam :PTChar; var ALen :Integer) :TLexType;
  var
    vCh :TChar;
  begin
    SkipSpacesAndComments(APtr);
    FCur := APtr;

    if APtr^ = #0 then
      Result := lexEOF
    else
    if (APtr^ = '"') or (APtr^ = '''') then begin
      FLen := 0;

      vCh := APtr^;
      Inc(APtr);
      AParam := APtr;
      {!!! ��������� ������������� ��������}
      {!!! ��������� ��������� �������? }
      while (APtr^ <> #0) and (APtr^ <> charCR) and (APtr^ <> charLF) and (APtr^ <> vCh) do
        Inc(APtr);

      if APtr^ <> vCh then
        Error(errUnclosedString);

      ALen := APtr - AParam;
      AddBuf(AParam, ALen);

      Inc(APtr);

      Result := lexString
    end else
    if (APtr^ >= '0') and (APtr^ <= '9') then begin

      AParam := APtr;
      while (APtr^ >= '0') and (APtr^ <= '9') do
        Inc(APtr);
      if CharIsWordChar(APtr^) then
        Error(errBadNumber);

      FLen := 0;
      ALen := APtr - AParam;
      AddBuf(AParam, ALen);

      Result := lexNumber
    end else
    if CharIsWordChar(APtr^) or (APtr^ = '$') then begin

      AParam := APtr;
      Inc(APtr);
      while (APtr^ <> #0) and CharIsWordChar(APtr^) do
        Inc(APtr);
      ALen := APtr - AParam;

      Result := lexWord;
    end else
    begin
      AParam := APtr;
      ALen := 1;
      Inc(APtr);
      Result := lexSymbol;
    end;
  end;


  procedure TMacroParser.SkipSpacesAndComments(var APtr :PTChar);
  begin
    while APtr^ <> #0 do begin
      if (APtr^ = ' ') or (APtr^ = charTab) then
        Inc(APtr)
      else
      if (APtr^ = charCR) or (APtr^ = charLF) then
        SkipCRLF(APtr)
      else
      if MatchStr(APtr, cLineComment1) or MatchStr(APtr, cLineComment2) then
        SkipLineComment(APtr)
      else
      if MatchStr(APtr, cInLineCommentBeg) then
        SkipMultilineComment(APtr)
      else
        Break;
    end;
  end;


  procedure TMacroParser.SkipLineComment(var APtr :PTChar);
  begin
    while (APtr^ <> #0) and not ((APtr^ = charCR) or (APtr^ = charLF)) do
      Inc(APtr);
  end;


  procedure TMacroParser.SkipMultilineComment(var APtr :PTChar);
  begin
    while (APtr^ <> #0) and not MatchStr(APtr, cInLineCommentEnd) do begin
      if (APtr^ = charCR) or (APtr^ = charLF) then
        SkipCRLF(APtr)
      else
        Inc(APtr);
    end;
    if APtr^ <> #0 then
      Inc(APtr, length(cInLineCommentEnd));
  end;


  procedure TMacroParser.SkipCRLF(var APtr :PTChar);
  begin
    if APtr^ = charCR then
      Inc(APtr);
    if APtr^ = charLF then
      Inc(APtr);
    Inc(FRow);
    FBeg := APtr;
    FCur := FBeg;
  end;


  procedure TMacroParser.ParseBindStr(APtr :PTChar; var ARes :TIntArray);
  var
    vBeg :PTChar;
    vKey :Integer;
    vBuf :array[0..255] of TChar;
  begin
    vBeg := APtr;
    while CanExtractNextWord(APtr, @vBuf[0], high(vBuf)) do begin
      vKey := FARSTD.FarNameToKey(@vBuf[0]);
      if vKey = -1 then
        Error(errBadHotkey, FRow, (FCur - FBeg) + (APtr - vBeg + 1));
      SetLength(ARes, Length(ARes) + 1);
      ARes[Length(ARes) - 1] := vKey;
    end;
  end;


  procedure TMacroParser.ParseAreaStr(APtr :PTChar; var ARes :DWORD);
  var
    vArea :Integer;
    vBeg :PTChar;
    vBuf :array[0..255] of TChar;
  begin
    vBeg := APtr;
    while CanExtractNextWord(APtr, @vBuf[0], high(vBuf)) do begin
      vArea := KeyAreas.GetKeyword(@vBuf[0], StrLen(@vBuf[0]));
      if vArea = -1 then
        Error(errBadMacroarea, FRow, (FCur - FBeg) + (APtr - vBeg + 1));
      ARes := ARes or (1 shl vArea);
    end;
  end;


  procedure TMacroParser.AddBuf(APtr :PTChar; ALen :Integer);
  begin
    if FLen + ALen + 1 > FSize then
      SetBufSize(FLen + ALen + 1);
    StrMove(FBuf + FLen, APtr, ALen);
    Inc(FLen, ALen);
    (FBuf + FLen)^ := #0;
  end;


  procedure TMacroParser.AddChars(AChr :TChar; ALen :Integer);
  begin
    if FLen + ALen + 1 > FSize then
      SetBufSize(FLen + ALen + 1);
    MemFillChar(FBuf + FLen, ALen, AChr);
    Inc(FLen, ALen);
    (FBuf + FLen)^ := #0;
  end;


  procedure TMacroParser.SetBufSize(ASize :Integer);
  const
    cAlign = $100;
  begin
    ASize := (((ASize + cAlign - 1) div cAlign) * cAlign);
    ReallocMem(FBuf, ASize * SizeOf(TChar));
    FSize := ASize;
  end;


  function TMacroParser.GetStrValue :TString;
  begin
    SetString(Result, FBuf, FLen);
  end;


  function TMacroParser.GetIntValue :Integer;
  var
    vErr :Integer;
  begin
    Val(FBuf, Result, vErr);
    if vErr <> 0 then
      Error(errBadNumber);
  end;


  procedure TMacroParser.NewMacro;
  begin
    FMacro.Name     := '';
    FMacro.Descr    := '';
    FMacro.Bind     := nil;
    FMacro.Area     := 0;
    FMacro.Cond     := 0;
    FMacro.Where    := '';
    FMacro.Text     := '';
    FMacro.Options  := [moDisableOutput, moSendToPlugins, moEatOnRun];
    FMacro.Row      := FRow;
    FMacro.Col      := FBeg - FCur;
  end;


  procedure SetMacroOption(var AOptions :TMacroOptions; AOption :TMacroOption; AOn :Boolean);
  begin
    if AOn then
      Include(AOptions, AOption)
    else
      Exclude(AOptions, AOption);
  end;


  procedure TMacroParser.SetMacroParam(AParam :Integer; ALex :TLexType);
  begin
    if (AParam in [kwName, kwDescr, kwBind, kwArea, kwWhere, kwCond]) and (Alex <> lexString) then
      Error(errExceptString);

    case AParam of
      kwName     : FMacro.Name  := GetStrValue;
      kwDescr    : FMacro.Descr := GetStrValue;
      kwBind     : ParseBindStr(FBuf, FMacro.Bind);
      kwArea     : ParseAreaStr(FBuf, FMacro.Area);
      kwCond     : {ParseCondStr(FBuf, FMacro.Cond)};
      kwWhere    : FMacro.Where := GetStrValue;
      kwSilence      : SetMacroOption(FMacro.Options, moDisableOutput, GetIntValue <> 0);
      kwSendPlug     : SetMacroOption(FMacro.Options, moSendToPlugins, GetIntValue <> 0);
      kwRunOnRelease : SetMacroOption(FMacro.Options, moRunOnRelease, GetIntValue <> 0);
      kwEatOnRun     : SetMacroOption(FMacro.Options, moEatOnRun, GetIntValue <> 0);
    end;
  end;


  procedure TMacroParser.AddMacro;
  begin
    if Assigned(FOnAdd) then
      FOnAdd(Self, FMacro);
  end;


  procedure TMacroParser.ShowError(E :EParseError);
  var
    vCode, vRow, vCol :Integer;
    vMessage :TString;
  begin
    if Assigned(FOnError) then begin
      vCode := E.HelpContext;
      if ParserResBase <> 0 then
        vMessage := GetMsg(ParserResBase + vCode);
      vRow := E.FRow;
      vCol := E.FCol;
      if (vRow = 0) and (vCol = 0)  then begin
        vRow := FRow;
        vCol := FCur - FBeg;
      end;
      FOnError(Self, vCode, vMessage, FFileName, vRow, vCol);
    end;
  end;


initialization
finalization
  FreeObj(Keywords);
  FreeObj(KeyAreas);
end.
