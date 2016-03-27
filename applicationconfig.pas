unit applicationconfig;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, libraryparser,inifiles,rcmdline,{$IFNDEF ANDROID}autoupdate,{$ENDIF}extendedhtmlparser,
accountlist{$IFNDEF ANDROID}, LMessages{$endif};

{$IFNDEF ANDROID}
const
   LM_SHOW_VIDELIBRI = LM_USER + $4224;
{$ENDIF}

type TErrorArray=array of record
                     error: string;
                     details: array of record
                       account: TCustomAccountAccess;
                       details, anonymouseDetails, libraryId, searchQuery: string;
                     end;
                   end;
  
const VIDELIBRI_MUTEX_NAME='VideLibriStarted';

type TCallbackHolder = class
  class procedure updateAutostart(enabled, askBeforeChange: boolean); virtual; static;
  class procedure applicationUpdate(auto:boolean); virtual; static;
  class procedure statusChange(const message: string); virtual; static;
  class procedure allThreadsDone(); virtual; static;
  class procedure postInitApplication(); virtual; static;
end;
TCallbackHolderClass = class of TCallbackHolder;

var programPath,userPath:string;
    machineConfig,userConfig: TIniFile;

    accounts: TAccountList;
    libraryManager: TLibraryManager=nil;

    cancelStarting,startToTNA:boolean;
    accountsRefreshedDate: longint=0; //set to currentDate

    currentDate:longint;
    lastCheck: integer;
    nextLimit:longint=MaxInt-1;
    nextNotExtendableLimit:longint=MaxInt;
    nextLimitStr: string;

    appFullTitle:string='VideLibri';
    versionNumber:integer=1830     ;
    //=>versionNumber/1000
    newVersionInstalled: boolean=false;

    {$IFDEF WIN32}startedMutex:THandle=0;{$ENDIF}

    exceptionStoring: TRTLCriticalSection;
    
    needApplicationRestart: boolean; //Soll das Programm nach Beenden neugestartet werden

    //TODO: customize colors in search panel colorSearchTextNotFound: tcolor=$6060FF;    //colorSearchTextFound: tcolor=clWindow;
    redTime: integer;
    RefreshInterval, WarnInterval: integer;
    lastWarnDate: integer;
    HistoryBackupInterval: longint;
    refreshAllAndIgnoreDate:boolean; //gibt an, dass alle Medien aktualisiert werden
                                     //sollen unabhängig vom letzten Aktualisierungdatum
    debugMode: boolean;

    errorMessageList:TErrorArray = nil;
    //oldErrorMessageList:TErrorArray = nil;
    oldErrorMessageString:string;

    callbacks: TCallbackHolderClass = TCallbackHolder;

  procedure initApplicationConfig;
  procedure finalizeApplicationConfig;

  procedure addErrorMessage(errorStr,errordetails, anonymouseDetails, libraryId, searchQuery:string;lib:TCustomAccountAccess=nil);
  procedure createErrorMessageStr(exception:exception; out errorStr,errordetails, anonymousDetails:string;account:TCustomAccountAccess=nil);

  procedure storeException(ex: exception; account:TCustomAccountAccess; libraryId, searchQuery: string); //thread safe

  //get the values the tna should have not the one it actually has
  //function getTNAHint():string;
  function getTNAIconBaseFileName():string;

  procedure updateGlobalAccountDates;
  procedure updateActiveInternetConfig;

  function DateToSimpleStr(const date: tdatetime):string;
  function DateToPrettyStr(const date: tdatetime):string;
  function DateToPrettyGrammarStr(preDate,preName:string;const date: tdatetime):string;
implementation
uses internetaccess,libraryaccess,math,FileUtil,bbutils,bbdebugtools,androidutils,
  {$IFDEF WIN32}
  windows,synapseinternetaccess,w32internetaccess
  {$ELSE}
  {$IFDEF ANDROID}
  androidinternetaccess
  {$ELSE}
  synapseinternetaccess
  {$ENDIF}
  {$ENDIF}
  ;

  procedure addErrorMessage(errorStr,errordetails, anonymouseDetails, libraryId, searchQuery:string;lib:TCustomAccountAccess=nil);
  var i:integer;
  begin
    for i:=0 to high(errorMessageList) do
      if errorMessageList[i].error=errorstr then begin
        SetLength(errorMessageList[i].details,length(errorMessageList[i].details)+1);
        errorMessageList[i].details[high(errorMessageList[i].details)].account:=lib;
        errorMessageList[i].details[high(errorMessageList[i].details)].details:=errordetails;
        errorMessageList[i].details[high(errorMessageList[i].details)].anonymouseDetails:=anonymouseDetails;
        errorMessageList[i].details[high(errorMessageList[i].details)].libraryId:=libraryId;
        errorMessageList[i].details[high(errorMessageList[i].details)].searchQuery:=searchQuery;
        exit;
      end;
    SetLength(errorMessageList,length(errorMessageList)+1);
    errorMessageList[high(errorMessageList)].error:=errorstr;
    setlength(errorMessageList[high(errorMessageList)].details,1);
    errorMessageList[high(errorMessageList)].details[0].account:=lib;
    errorMessageList[high(errorMessageList)].details[0].details:=errordetails;
    errorMessageList[high(errorMessageList)].details[0].anonymouseDetails:=anonymouseDetails;
    errorMessageList[high(errorMessageList)].details[0].libraryId:=libraryId;
    errorMessageList[high(errorMessageList)].details[0].searchQuery:=searchQuery;
  end;

  procedure createErrorMessageStr(exception: exception; out errorStr, errordetails, anonymousDetails: string; account: TCustomAccountAccess);
  var i:integer;
  begin
    errordetails:='';
    anonymousDetails:='';
    if exception is EInternetException then begin
      errorstr:=exception.message+#13#10#13#10+'Bitte überprüfen Sie Ihre Internetverbindung.';
      errordetails:=EInternetException(exception).details;
     end {else if exception is ELoginException then begin
      errorstr:=#13#10+exception.message;
     end }else if exception is ELibraryException then begin
      errorstr:=#13#10+exception.message;
      errordetails:=ELibraryException(exception).details;
     end else if exception is EHTMLParseMatchingException then begin
       errorstr:=//'Es ist folgender Fehler aufgetreten:      '#13#10+
            exception.className()+': '+ exception.message+'     ';
       if EHTMLParseMatchingException(exception).sender is THtmlTemplateParser then begin
         errordetails := THtmlTemplateParser(EHTMLParseMatchingException(exception).sender).debugMatchings(80);
         anonymousDetails := THtmlTemplateParser(EHTMLParseMatchingException(exception).sender).debugMatchings(80, false, ['class', 'id', 'style']);
       end;
     end else begin
      errorstr:=//'Es ist folgender Fehler aufgetreten:      '#13#10+
           exception.className()+': '+ exception.message+'     ';
     end;
    errordetails:=errordetails+#13#10'Detaillierte Informationen über die entsprechende Quellcodestelle:'#13#10+ BackTraceStrFunc(ExceptAddr);
    for i:=0 to ExceptFrameCount-1 do
      errordetails:=errordetails+#13#10+BackTraceStrFunc(ExceptFrames[i]);
    if logging then log('createErrorMessageStr: Exception: '+errorstr+#13#10'      Details: '+errordetails);
  end;

(*  function getTNAHint(): string;
  begin
    {if nextLimit>=MaxInt then
      result:='VideLibri'#13#10'Keine bekannte Abgabefrist'
     else if nextNotExtendableLimit=nextLimit then
      result:='VideLibri'#13#10'Nächste bekannte Abgabefrist:'#13#10+DateToPrettyStr(nextNotExtendableLimit)
     else
      result:='VideLibri'#13#10'Nächste bekannte Abgabefrist:'#13#10+DateToPrettyStr(nextLimit)+'  (verlängerbar)';}
     result:='
  end;        *)


  procedure storeException(ex: exception; account:TCustomAccountAccess; libraryId, searchQuery: string);
  var  errorstr, errordetails, anonymouseDetails: string;
  begin
    createErrorMessageStr(ex,errorstr,errordetails,anonymouseDetails, account);
    system.EnterCriticalSection(exceptionStoring);
    try
      addErrorMessage(errorstr,errordetails,anonymouseDetails, libraryId, searchQuery, account);
    finally
      system.LeaveCriticalSection(exceptionStoring);
    end;

  end;

  function getTNAIconBaseFileName(): string;
  begin
    if nextLimit<=redTime then
      result:='smallRed.ico'
     else if nextNotExtendableLimit=nextLimit then
      result:='smallYellow.ico'
     else
      result:='smallGreen.ico';
  end;

  procedure updateGlobalAccountDates;
  var i,j:integer;
  begin
    //set global nextLmiit and nextNotExtandable
    //(search next one)
    nextLimit:=MaxInt-1;
    nextNotExtendableLimit:=MaxInt;

    lastcheck:=currentDate;
    for i:=0 to accounts.count-1 do begin
      for j:=0 to accounts[i].books.current.count-1 do
        with (accounts[i]).books.current[j] do
          lastcheck:=min(lastcheck,lastExistsDate);
      if ((accounts[i]).books.nextLimit>0) then
         nextLimit:=min(nextLimit,(accounts[i]).books.nextLimit);
      if ((accounts[i]).books.nextNotExtendableLimit>0) then
        nextNotExtendableLimit:=min(nextNotExtendableLimit,(accounts[i]).books.nextNotExtendableLimit);
    end;
    nextLimitStr:=DateToPrettyStr(nextLimit);
    if nextLimit<>nextNotExtendableLimit then
      nextLimitStr:=nextLimitStr+' (verlängerbar)';
    callbacks.statusChange('Älteste angezeigte Daten sind '+dateToPrettyGrammarStr('vom ','von ',lastCheck));
  end;
  procedure updateActiveInternetConfig;
  begin
    {$IFDEF WIN32}
    defaultInternetAccessClass:=TW32InternetAccess;
    {$ELSE}
    {$IFDEF ANDROID}
    defaultInternetAccessClass:=TAndroidInternetAccess;
    {$ELSE}
    defaultInternetAccessClass:=TSynapseInternetAccess;
    {$ENDIF}
    {$ENDIF}
    {$IFNDEF ANDROID}
    case userConfig.readInteger('access','internet-backend',0) of
      1: {$IFDEF WIN32} defaultInternetAccessClass:=TW32InternetAccess{$ENDIF};
      2: defaultInternetAccessClass:=TSynapseInternetAccess;
    end;
    {$ENDIF}



    //    defaultInternetConfiguration.userAgent:='Mozilla 3.0 (compatible; VideLibri ';//2:13/20
    //    defaultInternetConfiguration.userAgent:='Mozilla 3.0 (compatible; VideLibri '+IntToStr(versionNumber);//+' '+machineConfig.ReadString('debug','userAgentAdd','')+')';
    defaultInternetConfiguration.userAgent:='Mozilla 3.0 (compatible; VideLibri '+IntToStr(versionNumber)+' '+machineConfig.ReadString('debug','userAgentAdd','')+')';
    if machineConfig.ReadString('debug','userAgentOverride','') <> '' then
      defaultInternetConfiguration.userAgent:=machineConfig.ReadString('debug','userAgentOverride','');
    if userConfig.ReadString('debug','userAgentOverride','') <> '' then
      defaultInternetConfiguration.userAgent:=userConfig.ReadString('debug','userAgentOverride','');
    //defaultInternetConfiguration.connectionCheckPage:='www.duesseldorf.de';
    case userConfig.readInteger('access','internet-type',0) of
      0: begin
        defaultInternetConfiguration.tryDefaultConfig:=true;
        defaultInternetConfiguration.useProxy:=false;
      end;
      1: begin
           defaultInternetConfiguration.tryDefaultConfig:=false;
           defaultInternetConfiguration.useProxy:=false;
         end;
      2: begin
           defaultInternetConfiguration.tryDefaultConfig:=false;
           defaultInternetConfiguration.useProxy:=true;
         end;
    end;
    defaultInternetConfiguration.proxyHTTPName:=userConfig.ReadString('access','httpProxyName','');
    defaultInternetConfiguration.proxyHTTPPort:=userConfig.ReadString('access','httpProxyPort','8080');
    defaultInternetConfiguration.proxyHTTPSName:=userConfig.ReadString('access','httpsProxyName','');
    defaultInternetConfiguration.proxyHTTPSPort:=userConfig.ReadString('access','httpsProxyPort','8080');
    defaultInternetConfiguration.proxySOCKSName:=userConfig.ReadString('access','socksProxyName','');
    defaultInternetConfiguration.proxySOCKSPort:=userConfig.ReadString('access','socksProxyPort','1080');
    defaultInternetConfiguration.checkSSLCertificates:=userConfig.ReadBool('access', 'checkCertificates', true);
  end;
  type EInitializationError = class(Exception);

  procedure initApplicationConfig;
  var i:integer;
      window,proc:THANDLE;

      commandLine:TCommandLineReader;
      //checkOne: boolean;
  begin
    currentDate:=trunc(now);

//    if currentDate>39264 then
  //     raiseInitializationError('Dises Betaversion ist abgelaufen (seit 1. Juli 2007).  Die neueste Version sollte unter www.benibela.de zu bekommen sein.');

    appFullTitle:='VideLibri '+FloatToStr(versionNumber / 1000);

    //Kommandozeile lesen
    commandLine:=TCommandLineReader.create;
    commandLine.declareFlag('autostart','Gibt an, ob das Programm automatisch gestartet wurde.');
    commandLine.declareFlag('start-always','Startet das Program auch, wenn es schon läuft.');
    commandLine.declareFlag('minimize','Gibt an, ob das Programm minimiert gestartet werden soll.');
    commandLine.declareInt('updated-to','Das Programm wurde auf Version ($1) aktualisiert (ACHTUNG: veraltet)',0);
    commandLine.declareInt('debug-addr-info','Wandelt in der Debugversion eine Adresse in eine Funktionszeile um',0);
    commandLine.declareFlag('log','Zeichnet alle Aktionen auf',false);
    commandLine.declareString               ('http-log-path','Pfad wo alle heruntergeladenen Dateien gespeichert werden sollen','');
    commandLine.declareFlag('refreshAll','Aktualisiert alle Medien',false);
    commandLine.declareString('debug-html-template','Führt ein Template aus (benötigt Datei)','');
    commandLine.declareString('on','Datei für das Template von debug-single-template','');
    commandLine.declareString('user-path','Pfad für Benutzereinstellungen','');
    commandLine.declareFlag('debug','Aktiviert einige debug-Funktionen');

    {if commandLine.readString('debug-html-template')<>'' then begin
      checkHTMLTemplate(commandLine.readString('debug-html-template'),commandLine.readString('on'));
      cancelStarting:=true;
      exit;
    end; ??}

    //Überprüft, ob das Programm schon gestart ist, und wenn ja, öffnet dieses
    {$IFDEF WIN32}
    SetLastError(0);
    startedMutex:=CreateMutex(nil,true,VIDELIBRI_MUTEX_NAME);
    if (not commandLine.readFlag('start-always')) and (GetLastError=ERROR_ALREADY_EXISTS) then begin
      window:=FindWindow(nil,pchar(appFullTitle));//FindWindow(nil,'VideLibri');
      if window<>0 then begin
        SetForegroundWindow(window); //important to allow the other instance to raise itself
        sendMessage(window, LM_SHOW_VIDELIBRI, 0,0);
        cancelStarting:=true;
        commandLine.free;
        exit;
      end;
    end;
    {$ENDIF}
  
    //Aktiviert das Logging
    logging:=commandLine.readFlag('log');
    if logging then log('Started with logging enabled, command line:'+ParamStr(0));

    defaultInternetConfiguration.logToPath:=commandLine.readString('http-log-path');
    if defaultInternetConfiguration.logToPath <>'' then
      defaultInternetConfiguration.logToPath:=IncludeTrailingPathDelimiter(defaultInternetConfiguration.logToPath);
    if logging then log('Started with internet logging enabled');

    //Pfade auslesen und überprüfen
    programPath:=ExtractFilePath(ParamStr(0));
    if not (programPath[length(programPath)] in ['/','\']) then programPath:=programPath+DirectorySeparator;
    assetPath:=programPath+'data'+DirectorySeparator; {$ifdef android}assetPath:='';{$endif}

    if logging then log('programPath is '+programPath);
    if logging then log('dataPath is '+assetPath);

    {$ifndef android}
    if not DirectoryExists(programPath) then
      raise EInitializationError.create('Programmpfad "'+programPath+'" wurde nicht gefunden');
    if not DirectoryExists(assetPath) then begin
      {$ifdef UNIX}
      if DirectoryExists('/usr/share/videlibri/data/') then
        assetPath:='/usr/share/videlibri/data/'
       else
      {$endif}
      raise EInitializationError.Create('Datenpfad "'+assetPath+'" wurde nicht gefunden');
    end;
    if logging and (not FileExists(assetPath+'machine.config')) then
      log('machine.config will be created');
    {$endif}

    //Globale Einstellungen lesen
    machineConfig:=iniFileFromString(assetFileAsString('machine.config'));
    if machineConfig.ReadInteger('version','number',versionNumber)<versionNumber then begin
      machineConfig.writeInteger('version','number',versionNumber);
      newVersionInstalled:=true;
    end;
    versionNumber:=machineConfig.ReadInteger('version','number',versionNumber);
    
    if logging then log('DATA-Version ist nun bekannt: '+inttostr(versionNumber));

    //Userpfad auslesen und überprüfen
    if commandLine.existsProperty('user-path') then
      userPath:=commandLine.readString('user-path')
     else
      userPath:=machineConfig.ReadString('paths','user',programPath+'config'+DirectorySeparator);
    if logging then log('plain user path: '+userPath);
    userPath:=StringReplace(userPath,'{$appdata}',getUserConfigPath,[rfReplaceAll,rfIgnoreCase]);
    if logging then log('replaced user path: '+userPath);
    if (copy(userpath,2,2)<>':\') and (copy(userpath,1,2)<>'\\') and (copy(userpath,1,1) <> '/') then
      userPath:=programPath+userpath;
    userPath:=IncludeTrailingPathDelimiter(userPath);
    if logging then log('finally user path: '+userPath);
    
    if not DirectoryExists(userPath) then begin
      try
        if logging then log('user path: '+userPath+' doesn''t exists');
        ForceDirectory(userPath);
        if logging then log('user path: '+userPath+' should be created');
        if not DirectoryExists(userPath) then
          raise EInitializationError.Create('Benutzerpfad "'+userPath+'" wurde nicht gefunden und konnte nicht erzeugt werden');
       except
         raise EInitializationError.Create('Benutzerpfad "'+userPath+'" wurde nicht gefunden und konnte nicht erzeugt werden');
       end;
    end;

    if logging and (not FileExists(userPath+'user.config')) then
      log('user.config will be created');

    //Userdaten lesen
    userConfig:=TIniFile.Create(userPath + 'user.config');
    RefreshInterval:=userConfig.ReadInteger('access','refresh-interval',1);
    WarnInterval:=userConfig.ReadInteger('base','warn-interval',0);
    lastWarnDate:=userConfig.ReadInteger('base','last-warn-date',0);
    HistoryBackupInterval:=userConfig.ReadInteger('base','history-backup-interval',30);

    {$ifdef android}logging:=logging or userConfig.ReadBool('base','logging',false);{$endif};

    libraryManager:=TLibraryManager.create();
    libraryManager.init(userPath);
    if libraryManager.enumeratePrettyLongNames()='' then
      raise EXCEPTION.Create('Keine Büchereitemplates im Verzeichnis '+assetPath+' vorhanden');

    accounts:=TAccountList.create(userPath+'account.list', libraryManager);
    accounts.load;

    nextLimitStr:=DateToPrettyStr(nextLimit);
    if nextLimit<>nextNotExtendableLimit then
      nextLimitStr:=nextLimitStr+' (verlängerbar)';


    if commandLine.readInt('debug-addr-info')<>0 then begin
      cancelStarting:=true;
      raise EInitializationError.create(BackTraceStrFunc(pointer(commandLine.readInt('debug-addr-info'))));
    end;

    if commandLine.readInt('updated-to')<>0 then
      userConfig.WriteInteger('version','number',commandLine.readInt('updated-to'));

    redTime:=trunc(now)+userConfig.ReadInteger('base','near-time',2);

    if commandLine.readFlag('autostart') then begin
      startToTNA:=userConfig.ReadBool('autostart','minimized',true);
      if (userConfig.ReadInteger('autostart','type',1)=1) then begin
        cancelStarting:=true;
        for i:=0 to accounts.count-1 do
          if ((accounts[i]).enabled) and (((accounts[i]).lastCheckDate<=currentDate-refreshInterval) or
             ((accounts[i]).existsCertainBookToExtend) or
             (((accounts[i]).books.nextLimit<>0)and((accounts[i]).books.nextLimit<=redTime))) then begin
            cancelStarting:=false;
            break;
          end;
      end else cancelStarting:=false;
    end else begin
      cancelStarting:=false;
      //TODO: Check autostart registry value (for later starts)
      if (not userConfig.SectionExists('autostart')) or
         (userConfig.ReadInteger('autostart','type',1)<>2) then
           callbacks.updateAutostart(true,true);
    end;
    if not cancelStarting then begin
      debugMode := commandLine.readFlag('debug');
      refreshAllAndIgnoreDate:=commandline.readFlag('refreshAll');

      updateActiveInternetConfig;

      fillchar(updateThreadConfig,sizeof(updateThreadConfig),0);
      InitCriticalSection(updateThreadConfig.libraryAccessSection);
      InitCriticalSection(updateThreadConfig.threadManagementSection);
      InitCriticalSection(updateThreadConfig.libraryFileAccess);
      InitCriticalSection(exceptionStoring);

      callbacks.postInitApplication();
    end;
    commandLine.free;
  end;
  
  procedure finalizeApplicationConfig;
  var i:integer;
  begin
    if logging then log('finalizeApplicationConfig started');
    if accounts<>nil then begin
      accounts.free;
      libraryManager.free;
      userConfig.free;
      machineConfig.free;
    end;

    if not cancelStarting then begin
      system.DoneCriticalsection(updateThreadConfig.libraryAccessSection);
      system.DoneCriticalsection(updateThreadConfig.threadManagementSection);
      system.DoneCriticalsection(updateThreadConfig.libraryFileAccess);
      system.DoneCriticalsection(exceptionStoring);
    end;

    {$IFDEF WIN32}
    if startedMutex<>0 then ReleaseMutex(startedMutex);
    if needApplicationRestart then
      WinExec(pchar(ParamStr(0)+' --start-always') ,SW_SHOWNORMAL);
    {$ENDIF}
    if logging then begin
      log('finalizeApplicationConfig ended'#13#10' => program will exit normally, after closing log');
      bbdebugtools.stoplogging();
    end;
    androidutils.uninit;
  end;

  function DateToSimpleStr(const date: tdatetime): string;
  begin
    result := dateTimeFormat(lowercase(FormatSettings.ShortDateFormat), date);
  end;

  function DateToPrettyStr(const date: tdatetime):string;
  begin
    if date=-2 then result:='nie'
    else if date=0 then result:='unbekannt'
    else case trunc(date-currentDate) of
      -2: result:='vorgestern';
      -1: result:='gestern';
      0: result:='heute';
      1: result:='morgen';
      2: result:='übermorgen';
      else result:=DateToSimpleStr(date);
    end;
  end;

  function DateToPrettyGrammarStr(preDate,preName: string; const date: tdatetime
    ): string;
  begin
    if date=-2 then result:='nie'
    else if date=0 then result:='unbekannt'
    else case trunc(date-currentDate) of
      -2: result:=preName+'vorgestern';
      -1: result:=preName+'gestern';
      0: result:=preName+'heute';
      1: result:=preName+'morgen';
      2: result:=preName+'übermorgen';
      else result:=preDate+DateToSimpleStr(date);
    end;
  end;


   class procedure TCallbackHolder.updateAutostart(enabled, askBeforeChange: boolean); begin end;
   class procedure TCallbackHolder.applicationUpdate(auto: boolean); begin end;
   class procedure TCallbackHolder.statusChange(const message: string); begin end;
   class procedure TCallbackHolder.allThreadsDone; begin end;
   class procedure TCallbackHolder.postInitApplication; begin end;

end.

