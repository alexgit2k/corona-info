; Corona 7-days incidence
EnableExplicit

; Structures
Structure area
  country.s
  name.s
  id.s
  incidence.s
EndStructure
Structure parser
  url.s
  startline.i
  columnline.i
  county.s
  urlHistory.s
  startlineHistory.i
  columnlineHistory.i
  daysHistory.i
  delimiter.s
EndStructure
Structure GraphValuesArray
  Array value.i(0)
EndStructure

; Configuration
Define configfile.s = "config.csv"
Global NewMap parsers.parser()
; DE
parsers("DE")\url = "https://raw.githubusercontent.com/jgehrcke/covid-19-germany-gae/master/more-data/latest-aggregate.csv"
parsers("DE")\columnline = 2
parsers("DE")\startline = 3
parsers("DE")\county = "county_name"
parsers("DE")\urlHistory = "https://raw.githubusercontent.com/jgehrcke/covid-19-germany-gae/master/more-data/7di-rki-by-ags.csv"
parsers("DE")\columnlineHistory = 1
parsers("DE")\startlineHistory = 2
parsers("DE")\daysHistory = 14
parsers("DE")\delimiter = ","
; AT
parsers("AT")\url = "https://covid19-dashboard.ages.at/data/CovidFaelle_GKZ.csv"
parsers("AT")\columnline = 1
parsers("AT")\startline = 2
parsers("AT")\county = "Bezirk"
parsers("AT")\urlHistory = "https://covid19-dashboard.ages.at/data/CovidFaelle_Timeline_GKZ.csv"
;parsers("AT")\urlHistory = ""
parsers("AT")\columnlineHistory = 1
parsers("AT")\startlineHistory = 2
parsers("AT")\daysHistory = 14
parsers("AT")\delimiter = ";"

; Variables
Global NewMap areas.area()
Global NewList areasSorted.s()
Global NewMap county2GraphValues.GraphValuesArray()
Define event
Define row
Define Dim GraphValues(0)

; GUI
XIncludeFile "corona-info-window.pbf"

; Graph
XIncludeFile "DrawSimpleGraph.pb"
Define graphWidth = 800, graphHeight = 600
Global graphWindow, graphCanvas, graphImg
Dim GraphValues(0)
NewMap GraphGeodata()

; Procedures
Declare Parse(type.s, country.s, Array output.s(1))
Declare DownloadAndParse(type.s, Map urls.parser())
Declare DownloadAndParseHistoryBackground(*dummy)
Declare ReadConfig(filename.s)
; Low-Level-Procedures
Declare text2array(input.s, Array output.s(1))
Declare column2index(line.s, delimiter.s, Map columns())
Declare split(String.s, Array StringArray.s(1), Separator.s = " ")

; --------------------------------------------------------------------------------------------------------------

; Window
OpenWindowMain()
AddGadgetItem(Viewer, -1, "Lade ...")
UpdateWindow_(GadgetID(Viewer)) ; Show immediately

; Config
ReadConfig(configfile)

; Download and parse latest data
DownloadAndParse("Latest", parsers())

; Output values
RemoveGadgetItem(Viewer, 0)
ForEach areasSorted()
  AddGadgetItem(Viewer, -1, areas(areasSorted())\name)
  SetGadgetItemText(Viewer, CountGadgetItems(Viewer)-1, areas(areasSorted())\incidence, 1)
Next

; Download and parse history data in Background
UpdateWindow_(GadgetID(Viewer)) ; Show immediately
CreateThread(@DownloadAndParseHistoryBackground(), @DownloadAndParseHistoryBackground())

; Wait for close
Repeat
  event = WaitWindowEvent()

  ; Show menu
  If event = #PB_Event_Gadget And EventType() = #PB_EventType_RightClick
    CreatePopupMenu(0)
    MenuItem(1, "In Zwischenablage kopieren")
    DisplayPopupMenu(0, WindowID(WindowMain))
  ; Copy to clipboard
  ElseIf event = #PB_Event_Menu And EventMenu() = 1
    row = SendMessage_(GadgetID(Viewer), #LVM_GETNEXTITEM, -1, #LVNI_SELECTED)
    If row <> -1
      SetClipboardText(GetGadgetItemText(Viewer, row) + ": " + GetGadgetItemText(Viewer, row, 1))
    EndIf
  EndIf
  
  ; Doubleclick
  If event = #PB_Event_Gadget And EventType() = #PB_EventType_LeftDoubleClick
    row = SendMessage_(GadgetID(Viewer), #LVM_GETNEXTITEM, -1, #LVNI_SELECTED)
    If row <> -1
      SelectElement(areasSorted(), row)
      ; Graph found
      If FindMapElement(county2GraphValues(), areas(areasSorted())\name)
        Debug "Graph for " + areas(areasSorted())\name
        Define i
        ; Show values
        ReDim GraphValues(ArraySize(county2GraphValues(areas(areasSorted())\name)\value())-1)
        For i = 0 To ArraySize(county2GraphValues(areas(areasSorted())\name)\value())-1
          Debug county2GraphValues(areas(areasSorted())\name)\value(i)
          GraphValues(i) = county2GraphValues(areas(areasSorted())\name)\value(i)
        Next
        Debug ""

        ; create image to receive output
        graphImg = CreateImage(#PB_Any, graphWidth, graphHeight, 24, $F0F0F0)
        DrawSimpleGraph(graphImg, GraphValues(), GraphGeodata(), 0, 1, 5, 12, $0000FF)

        ; Show graph
        graphWindow = OpenWindow(#PB_Any, 0, 0, graphWidth, graphHeight, "Corona-Historie: " + areas(areasSorted())\name + ", " +  Str(ArraySize(county2GraphValues(areas(areasSorted())\name)\value())) + " Tage", #PB_Window_SystemMenu | #PB_Window_ScreenCentered)
        graphCanvas = CanvasGadget(#PB_Any, 0, 0, graphWidth, graphHeight)
        SetGadgetAttribute(graphCanvas, #PB_Canvas_Image, ImageID(graphImg))
        FreeImage(graphImg)

        Repeat
        Until WaitWindowEvent() = #PB_Event_CloseWindow
        CloseWindow(graphWindow)

      Else
        Debug "No graph for '" + areas(areasSorted())\name + "'"
      EndIf
    EndIf
  EndIf

Until event = #PB_Event_CloseWindow
End

; --------------------------------------------------------------------------------------------------------------

Procedure Parse(type.s, country.s, Array output.s(1))
  Protected line.s
  Protected startline
  Protected delimiter.s
  Protected NewMap columns()
  Protected countyColumn
  Protected NewMap countyColumns()
  Protected key.s
  Protected i,j
  Protected Dim find.s(0)

  ; Unknown parser
  If Not FindMapElement(parsers(), country)
    MessageRequester("Error", "Unknown parser for country '" + country + "'")
    Debug "Unknown parser for country '" + country + "'"
    End
  EndIf
  
  Select type
      
    Case "Latest"
      ; Format options
      startline = parsers(country)\startline
      delimiter = parsers(country)\delimiter
      column2index(output(parsers(country)\columnline), delimiter, columns())
      countyColumn = columns(parsers(country)\county)
    
      ; Parse line by line
      For i=startline To ArraySize(output())
        line = output(i)
        ;Debug country + ": " + line
    
        ; Get area
        key = StringField(line, countyColumn, delimiter) ; area
        If Not FindMapElement(areas(),key) : Continue : EndIf
    
        ; Get 7-day incidence
        Select country
          ; DE
          Case "DE"
            areas(key)\incidence = StringField(line, columns("rki_cases_7di"), delimiter)
    
          ; AT
          Case "AT"
            areas(key)\incidence = StrF( ValF(StringField(line, columns("AnzahlFaelle7Tage"), delimiter)) * 100000 / ValF(StringField(line, columns("AnzEinwohner"), delimiter)), 1)
    
          ; Unknown
          Default
            Debug "Unknown parser for country '" + country + "'"
            MessageRequester("Error", "Unknown parser for country '" + country + "'")
        EndSelect
    
        ; Set decimal point
        areas(key)\incidence = ReplaceString(areas(key)\incidence, ".", ",")
        Debug "- " + key + " - " + areas(key)\incidence
    
      Next

    Case "History"
      ; Format options
      startline = parsers(country)\startlineHistory
      delimiter = parsers(country)\delimiter
      column2index(output(parsers(country)\columnlineHistory), delimiter, columns())

      Select country
        Case "DE"
          ; Get all county-columns
          ForEach areasSorted()
            If (areas(areasSorted())\country <> country) : Continue : EndIf
            countyColumns(areas(areasSorted())\name) = columns(areas(areasSorted())\id + "_7di")
          Next

          ; Last x days
          If (parsers(country)\daysHistory <> 0 And ArraySize(output())-parsers(country)\daysHistory+1 > startline)
            startline = ArraySize(output())-parsers(country)\daysHistory+1
            If (startline < parsers(country)\startlineHistory)
              startline = parsers(country)\startlineHistory
            EndIf
          EndIf

          ; Parse line by line
          For i=startline To ArraySize(output())
            line = output(i)
            Debug country + ": " + line

            ; Get for each county
            ForEach countyColumns()
              ; Get value
              key = StringField(line, countyColumns(), delimiter) ; value
              Debug "- " + MapKey(countyColumns()) + ": " + key

              ; Store
              county2GraphValues(MapKey(countyColumns()))\value(ArraySize(county2GraphValues(MapKey(countyColumns()))\value())) = Round(ValF(key), #PB_Round_Nearest)
              ReDim county2GraphValues(MapKey(countyColumns()))\value(ArraySize(county2GraphValues(MapKey(countyColumns()))\value())+1)
            Next

          Next

        Case "AT"
          ; Get all county-ids
          ForEach areasSorted()
            If (areas(areasSorted())\country <> country) : Continue : EndIf
            countyColumns(areas(areasSorted())\id) = 1
          Next

          ; Filter for counties
          j=0
          For i=startline To ArraySize(output())
            ;Debug Str(i) + ": " + output(i)
            key = StringField(output(i), columns("GKZ"), delimiter)
            If Not FindMapElement(countyColumns(),key) : Continue : EndIf
            Debug Str(i) + ": " + output(i)
            ReDim find.s(j)
            find(j) = output(i)
            j+1
          Next
          ReDim output(ArraySize(find()))
          CopyArray(find(), output())
          FreeArray(find())

          ; Last x days (x MapSize)
          If (parsers(country)\daysHistory <> 0 And ArraySize(output())-parsers(country)\daysHistory*MapSize(countyColumns())+1 > startline)
            startline = ArraySize(output())-parsers(country)\daysHistory*MapSize(countyColumns())+1
            If (startline < parsers(country)\startlineHistory)
              startline = parsers(country)\startlineHistory
            EndIf
          EndIf

          ; Parse line by line
          countyColumn = columns(parsers(country)\county)
          For i=startline To ArraySize(output())
            line = output(i)
            Debug country + ": " + line

            ; Calculate incidence for each county
            Debug areas(StringField(line, countyColumn, delimiter))\name
            county2GraphValues(areas(StringField(line, countyColumn, delimiter))\name)\value(ArraySize(county2GraphValues(areas(StringField(line, countyColumn, delimiter))\name)\value())) = ValF(StringField(line, columns("AnzahlFaelle7Tage"), delimiter)) * 100000 / ValF(StringField(line, columns("AnzEinwohner"), delimiter))
            ReDim county2GraphValues(areas(StringField(line, countyColumn, delimiter))\name)\value(ArraySize(county2GraphValues(areas(StringField(line, countyColumn, delimiter))\name)\value())+1)

          Next

    EndSelect

    ; Unknown
    Default
      Debug "Unknown parser for type '" + type + "'"
      MessageRequester("Error", "Unknown parser for type '" + type + "'")
  EndSelect

EndProcedure

Procedure DownloadAndParse(type.s, Map urls.parser())
  Protected content.s
  Protected Dim output.s(1)
  Protected i
  Protected *buffer
  Protected url.s
  InitNetwork()

  ; For each data-url
  ForEach urls()

    ; URL
    Select type.s
      Case "Latest"
        url = urls()\url
      Case "History"
        url = urls()\urlHistory
      ; Unknown
      Default
        Debug "Unknown type for download '" + type + "'"
        MessageRequester("Error", "Unknown type for download '" + type + "'")
    EndSelect

    ; Download
    Debug "Downloading " + url + " ..."
    Protected t = -ElapsedMilliseconds()
    *buffer = ReceiveHTTPMemory(url)
    Debug Str(t+ElapsedMilliseconds())+" ms"
    If Not *buffer
      Debug "Download failed: " + url
      MessageRequester("Error","Download failed: " + url)
      Continue
    EndIf

    ; Parse
    content = PeekS(*buffer, MemorySize(*buffer), #PB_UTF8|#PB_ByteLength)
    text2array(content, output())
    FreeMemory(*buffer)
    Parse(type, MapKey(urls()), output()) ; Parse(country, output())

  Next
EndProcedure

Procedure ReadConfig(filename.s)
  Protected content.s, key.s

  ; Open File
  If Not ReadFile(0, filename, #PB_UTF8)
    Debug "Unable to open file " + filename
    MessageRequester("Error","Unable to open file " + filename)
    ProcedureReturn
  EndIf

  While Eof(0) = 0
    content = ReadString(0,#PB_UTF8)

    ; Skip comments
    If Left(content, 1) = "#" : Continue : EndIf

    ; Parse
    Debug content
    ; Hash for values
    key = StringField(content, 2, ",") ; area
    areas(key)\country = StringField(content, 1, ",")
    ; DE: Move SK/LK to end
    If Left(key,3) = "LK " Or Left(key,3) = "SK "
      areas()\name = Right(key,Len(key)-3) + " (" + Left(key,2) + ")"
    ; AT: Space before (Stadt)
    ElseIf Right(key,7) = "(Stadt)"
      areas()\name = Left(key,Len(key)-7) + " (Stadt)"
    Else
      areas()\name = key
    EndIf
    ; id (AGS / GKZ)
    areas()\id = StringField(content, 3, ",")
    ; List for sorting
    AddElement(areasSorted())
    areasSorted() = key

  Wend
  CloseFile(0)

EndProcedure

; --------------------------------------------------------------------------------------------------------------
; Low-Level

Procedure text2array(input.s, Array output.s(1))
  Protected eol.s
  Protected i

  ; Detect EOL
  If CountString(input, #CRLF$) > 0
    eol = #CRLF$
  ElseIf CountString(input, #LF$) > 0
    eol = #LF$
  ElseIf CountString(input, #CR$) > 0
    eol = #CR$
  Else
    Debug "Unable to detect line ending, assuming only one line!"
    output(1) = input
    ProcedureReturn
  EndIf

  ; Split
  Debug Str(CountString(input,eol)+1) + " lines found."
  split(input, output(), eol)
  ; Unshift
  ReDim output(CountString(input,eol)+1)
  For i=CountString(input,eol) To 0 Step -1
    output(i+1) = output(i)
  Next
  output(0) = ""

  ; Last line empty
  If output(ArraySize(output())) = ""
    ReDim output(CountString(input,eol))
  EndIf

EndProcedure

Procedure column2index(line.s, delimiter.s, Map columns())
  Protected key.s
  Protected i
  ; Get all columns
  For i=1 To CountString(line, delimiter)+1
    Debug Str(i) + ": " + StringField(line, i, delimiter)
    key = StringField(line, i, delimiter)
    columns(key) = i
  Next
EndProcedure

; wilbert: https://www.purebasic.fr/english/viewtopic.php?p=486360#p486360
Procedure split(String.s, Array StringArray.s(1), Separator.s = " ")
  Protected S.String, *S.Integer = @S
  Protected.i asize, i, p, slen
  asize = CountString(String, Separator)
  slen = Len(Separator)
  ReDim StringArray(asize)

  *S\i = @String
  While i < asize
    p = FindString(S\s, Separator)
    StringArray(i) = PeekS(*S\i, p - 1)
    ; Debug "- " + StringArray(i)
    *S\i + (p + slen - 1) << #PB_Compiler_Unicode
    i + 1
  Wend
  StringArray(i) = S\s
  *S\i = 0
EndProcedure

Procedure DownloadAndParseHistoryBackground(*dummy)
  Debug "Running parser in background ..."
  DownloadAndParse("History", parsers())
  Debug "Finished parser in background!"
EndProcedure

; IDE Options = PureBasic 5.73 LTS (Windows - x86)
; CursorPosition = 81
; FirstLine = 58
; Folding = -
; EnableXP
; UseIcon = icon.ico
; Executable = corona-info.exe