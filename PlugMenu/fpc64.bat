@Echo off

if /i NOT "%1" == "Far3" (
  echo Not supported
  goto :EOF
)

call ..\_fpc.bat PlugMenu 64 %*