; Corona 7-days incidence
EnableExplicit

; Structures
Structure area
  country.s
  name.s
  incidence.s
EndStructure
Structure parser
  url.s
  startline.i
  columnline.i
  delimiter.s
  county.s
EndStructure

; Configuration
Define configfile.s = "config.csv"
Global NewMap parsers.parser()
; DE
parsers("DE")\url = "https://raw.githubusercontent.com/jgehrcke/covid-19-germany-gae/master/more-data/latest-aggregate.csv"
parsers("DE")\delimiter = ","
parsers("DE")\columnline = 2
parsers("DE")\startline = 3
parsers("DE")\county = "county_name"
; AT
parsers("AT")\url = "https://covid19-dashboard.ages.at/data/CovidFaelle_GKZ.csv"
parsers("AT")\delimiter = ";"
parsers("AT")\columnline = 1
parsers("AT")\startline = 2
parsers("AT")\county = "Bezirk"

; Variables
Global NewMap areas.area()
Global NewList areasSorted.s()
Define event
Define row

; GUI
XIncludeFile "corona-info-window.pbf"

; Procedures
Declare Parse(country.s, Array output.s(1))
Declare DownloadAndParse(Map urls.parser())
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

; Download and parse data
DownloadAndParse(parsers())

; Output values
RemoveGadgetItem(Viewer, 0)
ForEach areasSorted()
  AddGadgetItem(Viewer, -1, areas(areasSorted())\name)
  SetGadgetItemText(Viewer, CountGadgetItems(Viewer)-1, areas(areasSorted())\incidence, 1)
Next

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

Until event = #PB_Event_CloseWindow
End

; --------------------------------------------------------------------------------------------------------------

Procedure Parse(country.s, Array output.s(1))
  Protected line.s
  Protected startline
  Protected delimiter.s
  Protected NewMap columns()
  Protected countyColumn
  Protected key.s
  Protected i

  ; Unknown parser
  If Not FindMapElement(parsers(), country)
    MessageRequester("Error", "Unknown parser for country '" + country + "'")
    Debug "Unknown parser for country '" + country + "'"
    End
  EndIf

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
EndProcedure

Procedure DownloadAndParse(Map urls.parser())
  Protected content.s
  Protected Dim output.s(1)
  Protected i
  Protected *buffer
  InitNetwork()

  ; For each data-url
  ForEach urls()

    ; Download
    Debug "Downloading " + urls()\url + " ..."
    *buffer = ReceiveHTTPMemory(urls()\url)
    If Not *buffer
      Debug "Download failed: " + urls()\url
      MessageRequester("Error","Download failed: " + urls()\url)
      Continue
    EndIf

    ; Parse
    content = PeekS(*buffer, MemorySize(*buffer), #PB_UTF8|#PB_ByteLength)
    text2array(content, output())
    FreeMemory(*buffer)
    Parse(MapKey(urls()), output()) ; Parse(country, output())

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

; IDE Options = PureBasic 5.73 LTS (Windows - x86)
; CursorPosition = 81
; FirstLine = 58
; Folding = -
; EnableXP
; UseIcon = icon.ico
; Executable = corona-info.exe