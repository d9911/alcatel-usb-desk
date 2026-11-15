function Show-AlcatelDesktop([switch]$SmokeTest) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -Path (Join-Path $PSScriptRoot 'Alcatel.Desktop.cs') -ReferencedAssemblies System.Windows.Forms, System.Drawing, System
    [Windows.Forms.Application]::EnableVisualStyles()
    [Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
    $preferencePath = Join-Path $script:ProjectRoot 'config\settings.local.json'
    if ($SmokeTest) {
        $testDirectory = Join-Path $script:ProjectRoot 'TestResults'
        [void][IO.Directory]::CreateDirectory($testDirectory)
        $preferencePath = Join-Path $testDirectory ('language-' + [guid]::NewGuid().ToString('N') + '.json')
        $script:Settings = Read-Settings $preferencePath
    }
    $languageCodes = @('en', 'ru', 'es')
    $script:Strings = Get-Strings $script:Settings.language
    $script:Sessions = @{}
    $script:Devices = @()
    $script:PhoneSerial = ''
    $script:Updating = $false
    $script:PendingWork = $null
    $script:UiTestError = $null
    $script:Localized = @{}
    $feed = New-Object Alcatel.Desktop.LogFeed((Join-Path $script:ProjectRoot 'logs'))
    $ink = [Drawing.Color]::FromArgb(32, 47, 57)
    $muted = [Drawing.Color]::FromArgb(103, 118, 128)
    $accent = [Drawing.Color]::FromArgb(29, 104, 99)
    $form = New-Object Windows.Forms.Form
    $form.Text = 'Alcatel USB Desk'
    $form.StartPosition = 'CenterScreen'
    $form.ClientSize = New-Object Drawing.Size(1120, 800)
    $form.MinimumSize = New-Object Drawing.Size(1040, 740)
    $form.AutoScaleMode = 'Dpi'
    $form.Font = New-Object Drawing.Font('Segoe UI', 10.5)
    $form.ForeColor = $ink
    $form.BackColor = [Drawing.Color]::FromArgb(242, 245, 246)

    function New-Table([int]$Columns = 1) {
        $table = New-Object Windows.Forms.TableLayoutPanel
        $table.Dock = 'Fill'; $table.ColumnCount = $Columns
        $table.Margin = New-Object Windows.Forms.Padding(0)
        $table.BackColor = [Drawing.Color]::Transparent
        $table
    }
    function Add-CellRow($Table, $Control, [int]$Height) {
        $row = $Table.RowCount; $Table.RowCount++
        [void]$Table.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute', $Height)))
        $Control.Dock = 'Fill'; $Control.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 6)
        $Table.Controls.Add($Control, 0, $row)
    }
    function New-Label([string]$Key, [switch]$Heading) {
        $label = New-Object Alcatel.Desktop.SmoothLabel
        $label.Text = $script:Strings.$Key
        $label.UseCompatibleTextRendering = $false
        $label.BackColor = [Drawing.Color]::Transparent
        $label.ForeColor = if ($Heading) { $ink } else { $muted }
        $label.TextAlign = 'MiddleLeft'
        if ($Heading) { $label.Font = New-Object Drawing.Font('Segoe UI Semibold', 11) }
        $script:Localized[$Key] = $label
        $label
    }
    function New-Button([string]$Key, [int]$Width = 150, [switch]$Primary) {
        $button = New-Object Alcatel.Desktop.ActionButton
        $button.Text = $script:Strings.$Key; $button.Width = $Width; $button.Primary = [bool]$Primary
        $script:Localized[$Key] = $button
        $button
    }
    function New-Pair($First, $Second, [int]$SecondWidth) {
        $table = New-Table 2
        [void]$table.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
        [void]$table.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', $SecondWidth)))
        $First.Dock = $Second.Dock = 'Fill'
        $First.Margin = New-Object Windows.Forms.Padding(0, 0, 10, 0)
        $Second.Margin = New-Object Windows.Forms.Padding(0)
        $table.Controls.Add($First, 0, 0); $table.Controls.Add($Second, 1, 0)
        $table
    }
    function New-Flow {
        $panel = New-Object Windows.Forms.FlowLayoutPanel
        $panel.WrapContents = $false; $panel.BackColor = [Drawing.Color]::Transparent
        $panel.Margin = New-Object Windows.Forms.Padding(0)
        $panel
    }
    function New-Card {
        $card = New-Object Alcatel.Desktop.Card
        $body = New-Table
        $card.Controls.Add($body)
        [pscustomobject]@{ Panel = $card; Body = $body }
    }

    $root = New-Table
    $root.Padding = New-Object Windows.Forms.Padding(24, 18, 24, 12)
    $form.Controls.Add($root)
    $header = New-Pair (New-Table) (New-Table) 250
    $branding = $header.GetControlFromPosition(0, 0)
    $heading = New-Label 'title' -Heading
    $heading.Font = New-Object Drawing.Font('Segoe UI Semibold', 23)
    Add-CellRow $branding $heading 43
    Add-CellRow $branding (New-Label 'subtitle') 29
    $languageBody = $header.GetControlFromPosition(1, 0)
    $languageBox = New-Object Windows.Forms.ComboBox
    $languageBox.DropDownStyle = 'DropDownList'; $languageBox.FlatStyle = 'Flat'
    $languageBox.AccessibleName = $script:Strings.language
    Add-CellRow $languageBody $languageBox 36
    $spanish = New-Object Windows.Forms.CheckBox
    $spanish.Text = $script:Strings.spanish; $spanish.Checked = $script:Settings.enableSpanish
    $spanish.Font = New-Object Drawing.Font('Segoe UI', 9)
    $script:Localized['spanish'] = $spanish
    Add-CellRow $languageBody $spanish 28
    Add-CellRow $root $header 90

    $columns = New-Table 2
    [void]$columns.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 56)))
    [void]$columns.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 44)))
    $row = $root.RowCount; $root.RowCount++
    [void]$root.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 100)))
    $root.Controls.Add($columns, 0, $row)
    $leftScroll = New-Object Windows.Forms.Panel
    $leftScroll.Dock = 'Fill'; $leftScroll.AutoScroll = $true
    $leftScroll.Margin = New-Object Windows.Forms.Padding(0, 0, 16, 0)
    $columns.Controls.Add($leftScroll, 0, 0)
    $left = New-Table; $left.Dock = 'Top'; $left.AutoSize = $true
    $leftScroll.Controls.Add($left)

    $deviceCard = New-Card
    Add-CellRow $deviceCard.Body (New-Label 'device' -Heading) 30
    $deviceBox = New-Object Windows.Forms.ComboBox
    $deviceBox.DropDownStyle = 'DropDownList'; $deviceBox.FlatStyle = 'Flat'
    $refresh = New-Button 'refresh'
    Add-CellRow $deviceCard.Body (New-Pair $deviceBox $refresh 156) 42
    $connection = New-Object Alcatel.Desktop.SmoothLabel
    $connection.ForeColor = $accent; $connection.TextAlign = 'MiddleLeft'
    Add-CellRow $deviceCard.Body $connection 27
    $phone = New-Button 'phone' 175 -Primary
    $keyboard = New-Button 'keyboard' 280
    Add-CellRow $deviceCard.Body (New-Pair $phone $keyboard 285) 46
    $scrollHint = New-Label 'scrollHelp'
    $scrollHint.Font = New-Object Drawing.Font('Segoe UI', 9)
    Add-CellRow $deviceCard.Body $scrollHint 49
    Add-CellRow $left $deviceCard.Panel 246

    $cameraCard = New-Card
    Add-CellRow $cameraCard.Body (New-Label 'cameraSection' -Heading) 30
    $rotationLabel = New-Label 'rotation'
    $cropLabel = New-Label 'crop'
    Add-CellRow $cameraCard.Body (New-Pair $cropLabel $rotationLabel 145) 25
    $rotationBox = New-Object Windows.Forms.ComboBox
    $rotationBox.DropDownStyle = 'DropDownList'; $rotationBox.FlatStyle = 'Flat'
    [void]$rotationBox.Items.AddRange(@('0', '90', '180', '270'))
    $rotationBox.SelectedItem = [string]$script:Settings.cameraRotation
    $cropBox = New-Object Windows.Forms.TextBox
    $cropBox.Text = $script:Settings.cameraCrop; $cropBox.BorderStyle = 'FixedSingle'
    Add-CellRow $cameraCard.Body (New-Pair $cropBox $rotationBox 145) 35
    $cameraHint = New-Label 'cameraSummary'
    $cameraHint.Font = New-Object Drawing.Font('Segoe UI', 9)
    Add-CellRow $cameraCard.Body $cameraHint 42
    $camera = New-Button 'camera' 170
    $diagnostics = New-Button 'diagnostics' 260
    Add-CellRow $cameraCard.Body (New-Pair $camera $diagnostics 265) 46
    Add-CellRow $left $cameraCard.Panel 224

    $footer = New-Table 3
    foreach ($width in @(31, 34, 35)) { [void]$footer.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', $width))) }
    $stop = New-Button 'stop' 167
    $save = New-Button 'save' 180
    $help = New-Button 'help' 175
    $footerColumn = 0
    foreach ($button in @($stop, $save, $help)) { $button.Dock = 'Fill'; $footer.Controls.Add($button, $footerColumn++, 0) }
    Add-CellRow $left $footer 48
    $tips = New-Button 'connectionGuide'
    Add-CellRow $left $tips 40
    $helpCard = New-Card
    Add-CellRow $helpCard.Body (New-Label 'keyboardHelp') 130
    Add-CellRow $helpCard.Body (New-Label 'cameraHelp') 95
    $helpCard.Panel.Visible = $false
    Add-CellRow $left $helpCard.Panel 0
    $tips.Add_Click({
        $helpCard.Panel.Visible = -not $helpCard.Panel.Visible
        $left.RowStyles[$left.RowCount - 1].Height = if ($helpCard.Panel.Visible) { 285 } else { 0 }
    })

    $journalCard = New-Card
    $journalCard.Panel.Dock = 'Fill'
    $columns.Controls.Add($journalCard.Panel, 1, 0)
    Add-CellRow $journalCard.Body (New-Label 'journal' -Heading) 30
    $journal = New-Object Windows.Forms.TextBox
    $journal.Multiline = $true; $journal.ScrollBars = 'Vertical'
    $journal.ReadOnly = $true; $journal.BorderStyle = 'None'; $journal.BackColor = [Drawing.Color]::White
    $journal.ForeColor = $ink; $journal.Font = New-Object Drawing.Font('Consolas', 9.5)
    $journal.WordWrap = $true
    $journal.AccessibleName = $script:Strings.journal
    $row = $journalCard.Body.RowCount; $journalCard.Body.RowCount++
    [void]$journalCard.Body.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 100)))
    $journal.Dock = 'Fill'; $journal.Margin = New-Object Windows.Forms.Padding(0, 8, 0, 12)
    $journalCard.Body.Controls.Add($journal, 0, $row)
    $journalActions = New-Flow
    $clear = New-Button 'clearJournal' 110
    $logs = New-Button 'logs' 150
    $journalActions.Controls.AddRange(@($clear, $logs))
    Add-CellRow $journalCard.Body $journalActions 44
    $status = New-Object Alcatel.Desktop.SmoothLabel
    $status.ForeColor = $muted; $status.TextAlign = 'MiddleLeft'
    Add-CellRow $root $status 34

    function Add-Journal([string]$Text, [string]$Source = 'USB', [switch]$ErrorEntry) {
        foreach ($line in ($Text -split '\r?\n')) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($journal.TextLength -gt 60000) {
                $journal.Select(0, 20000); $journal.SelectedText = ''
            }
            $journal.Select($journal.TextLength, 0)
            $marker = if ($ErrorEntry) { 'ERROR ' } else { '' }
            $journal.AppendText(('[' + [DateTime]::Now.ToString('HH:mm:ss') + '] ' + $marker + $Source + '  ' + $line + [Environment]::NewLine))
        }
        $journal.ScrollToCaret()
    }
    function Poll-Logs {
        foreach ($line in $feed.Poll()) {
            Add-Journal $line.Text $line.Source -ErrorEntry:($line.Text -match '(?i)\b(ERROR|FATAL|Exception|failed)\b')
        }
    }
    function Update-Controls {
        $busy = $null -ne $script:PendingWork
        $selected = $deviceBox.SelectedIndex -ge 0 -and $deviceBox.SelectedIndex -lt $script:Devices.Count
        $ready = $selected -and $script:Devices[$deviceBox.SelectedIndex].State -eq 'device'
        $refresh.Enabled = -not $busy
        foreach ($button in @($phone, $camera, $keyboard, $diagnostics)) { $button.Enabled = -not $busy -and $ready }
        $stop.Enabled = -not $busy -and $script:Sessions.Count -gt 0
        $deviceBox.Enabled = -not $busy
        $connection.Text = if ($selected) { $script:Devices[$deviceBox.SelectedIndex].Label } else { $script:Strings.noDevices }
        $connection.ForeColor = if ($ready) { $accent } else { $muted }
    }
    function Update-Language {
        $script:Updating = $true
        try {
            $languageBox.Items.Clear(); [void]$languageBox.Items.AddRange(@('English', 'Русский'))
            if ($spanish.Checked) { [void]$languageBox.Items.Add('Español') }
            if (-not $spanish.Checked -and $script:Settings.language -eq 'es') { $script:Settings.language = 'en' }
            $languageBox.SelectedIndex = $languageCodes.IndexOf($script:Settings.language)
            $script:Strings = Get-Strings $script:Settings.language
            foreach ($key in $script:Localized.Keys) { $script:Localized[$key].Text = $script:Strings.$key }
            $languageBox.AccessibleName = $script:Strings.language
            $journal.AccessibleName = $script:Strings.journal
            $status.Text = if ($null -ne $script:PendingWork) { $script:Strings.('operation' + $script:PendingWork.Kind) }
                elseif ($deviceBox.SelectedIndex -ge 0 -and $script:Devices[$deviceBox.SelectedIndex].State -eq 'device') { $script:Strings.deviceReady }
                else { $script:Strings.ready }
            Update-Controls
        } finally { $script:Updating = $false }
    }
    function Get-UiError($Exception) {
        while ($null -ne $Exception.InnerException) { $Exception = $Exception.InnerException }
        $Exception.Message
    }
    function Invoke-Ui([scriptblock]$Work) {
        try { & $Work } catch {
            $status.Text = Get-UiError $_.Exception
            Add-Journal $status.Text $script:Strings.error -ErrorEntry
        }
    }
    function Sync-Settings {
        $script:Settings.cameraRotation = [int]$rotationBox.SelectedItem
        $script:Settings.cameraCrop = $cropBox.Text.Trim(); $script:Settings.enableSpanish = $spanish.Checked
        if ($deviceBox.SelectedIndex -ge 0) { $script:Settings.serial = $script:Devices[$deviceBox.SelectedIndex].Serial }
        Assert-Settings $script:Settings
    }
    function Start-UiWork([string]$Kind) {
        if ($null -ne $script:PendingWork) { return }
        if ($Kind -ne 'Discover') { Sync-Settings }
        $serial = if ($deviceBox.SelectedIndex -ge 0) { $script:Devices[$deviceBox.SelectedIndex].Serial } else { $script:Settings.serial }
        if ($Kind -ne 'Discover' -and -not $serial) { throw $script:Strings.selectDevice }
        $reuse = $Kind -eq 'Keyboard' -and $script:Sessions.ContainsKey('Phone') -and -not $script:Sessions.Phone.HasExited -and $script:PhoneSerial -eq $serial
        $work = [PowerShell]::Create()
        [void]$work.AddScript({
            param($core, $kind, $serial, $settingsJson, $reuse, $fixture)
            $ErrorActionPreference = 'Stop'
            . $core
            if ($fixture) {
                Start-Sleep -Milliseconds 150
                if ($kind -eq 'Info') { throw 'Fixture USB disconnected' }
                return [pscustomobject]@{ Devices = @([pscustomobject]@{ Serial = 'demo-usb'; State = 'device'; Label = 'Alcatel 1S  /  USB'; Model = '5024D_RU' }) }
            }
            if ($kind -eq 'Discover') { return [pscustomobject]@{ Devices = @(Get-Devices) } }
            $device = Resolve-Device @(Get-Devices) $serial
            if ($kind -eq 'Info') { return [pscustomobject]@{ Report = (Get-DeviceReport $device.Serial) -join [Environment]::NewLine } }
            $settings = $settingsJson | ConvertFrom-Json
            $process = $null
            try {
                if ($kind -ne 'Keyboard' -or -not $reuse) {
                    $mode = if ($kind -eq 'Camera') { 'Camera' } else { 'Phone' }
                    $process = Start-Mirror $settings $device.Serial $mode
                }
                if ($kind -eq 'Keyboard') {
                    $deadline = [DateTime]::UtcNow.AddSeconds(10)
                    do {
                        $state = (Invoke-Adb @('-s', $device.Serial, 'shell', 'dumpsys', 'input')).Output
                        if ($state -match '(?m)^\s+\d+: scrcpy\s*$') { break }
                        Start-Sleep -Milliseconds 250
                    } while ([DateTime]::UtcNow -lt $deadline)
                    if ($state -notmatch '(?m)^\s+\d+: scrcpy\s*$') { throw 'UHID keyboard was not detected. Check the phone session logs.' }
                    [void](Open-KeyboardSettings $device.Serial)
                }
                [pscustomobject]@{ Process = $process; Serial = $device.Serial; LogPrefix = if ($null -ne $process) { $process.LogPrefix } else { '' } }
            } catch {
                if ($null -ne $process -and -not $process.HasExited) { [void]$process.CloseMainWindow() }
                throw
            }
        }.ToString()).AddArgument((Join-Path $script:ProjectRoot 'src\Alcatel.Core.ps1')).AddArgument($Kind).AddArgument($serial).AddArgument(($script:Settings | ConvertTo-Json)).AddArgument($reuse).AddArgument([bool]$SmokeTest)
        try {
            $script:PendingWork = [pscustomobject]@{ PowerShell = $work; Async = $work.BeginInvoke(); Kind = $Kind; Previous = $serial }
        } catch { $work.Dispose(); throw }
        $status.Text = $script:Strings.('operation' + $Kind)
        Add-Journal $status.Text
        Update-Controls
    }
    function Complete-UiWork {
        if ($null -eq $script:PendingWork -or -not $script:PendingWork.Async.IsCompleted) { return }
        $task = $script:PendingWork
        try {
            $results = @($task.PowerShell.EndInvoke($task.Async))
            if ($task.PowerShell.Streams.Error.Count -gt 0) { throw $task.PowerShell.Streams.Error[0].Exception }
            if ($results.Count -ne 1) { throw 'Unexpected device operation result.' }
            $result = $results[0]
            if ($task.Kind -eq 'Discover') {
                $script:Devices = @($result.Devices)
                $deviceBox.Items.Clear()
                foreach ($device in $script:Devices) { [void]$deviceBox.Items.Add($device.Label); Add-Journal $device.Label }
                for ($i = 0; $i -lt $script:Devices.Count; $i++) { if ($script:Devices[$i].Serial -eq $task.Previous) { $deviceBox.SelectedIndex = $i } }
                if ($script:Devices.Count -eq 1 -and -not $task.Previous) { $deviceBox.SelectedIndex = 0 }
                $status.Text = if ($deviceBox.SelectedIndex -ge 0 -and $script:Devices[$deviceBox.SelectedIndex].State -eq 'device') { $script:Strings.deviceReady }
                    elseif ($script:Devices.Count) { $script:Strings.selectDevice } else { $script:Strings.noDevices }
                Add-Journal $status.Text
            } elseif ($task.Kind -eq 'Info') {
                Add-Journal $result.Report
                $status.Text = $script:Strings.deviceReady
            } else {
                if ($null -ne $result.Process) {
                    $mode = if ($task.Kind -eq 'Camera') { 'Camera' } else { 'Phone' }
                    if ($script:Sessions.ContainsKey($mode)) { $script:Sessions[$mode].Dispose() }
                    $script:Sessions[$mode] = $result.Process
                    if ($mode -eq 'Phone') { $script:PhoneSerial = $result.Serial }
                    foreach ($suffix in @('stdout', 'stderr', 'scroll.stdout', 'scroll.stderr')) {
                        $feed.Attach(($result.LogPrefix + '.' + $suffix + '.log'), ($mode + '/' + $suffix))
                    }
                }
                $status.Text = if ($task.Kind -eq 'Keyboard') { $script:Strings.keyboardReady } else { $script:Strings.started }
                Add-Journal $status.Text
                Save-Settings $script:Settings $preferencePath
            }
        } catch {
            $status.Text = Get-UiError $_.Exception; Add-Journal $status.Text $script:Strings.error -ErrorEntry
        } finally {
            $task.PowerShell.Dispose(); $script:PendingWork = $null; Update-Controls
        }
    }
    function Stop-Session([string]$Mode) {
        if (-not $script:Sessions.ContainsKey($Mode)) { return }
        $process = $script:Sessions[$Mode]
        if (-not $process.HasExited -and (-not $process.CloseMainWindow() -or -not $process.WaitForExit(4000))) { throw 'Close the scrcpy window manually, then retry.' }
        $process.Dispose(); $script:Sessions.Remove($Mode)
        Add-Journal ($Mode + ': ' + $script:Strings.stopped)
    }

    $refresh.Add_Click({ Invoke-Ui { Start-UiWork 'Discover' } })
    $phone.Add_Click({ Invoke-Ui { Start-UiWork 'Phone' } })
    $camera.Add_Click({ Invoke-Ui { Start-UiWork 'Camera' } })
    $keyboard.Add_Click({ Invoke-Ui { Start-UiWork 'Keyboard' } })
    $diagnostics.Add_Click({ Invoke-Ui { Start-UiWork 'Info' } })
    $deviceBox.Add_SelectedIndexChanged({ Update-Controls })
    $stop.Add_Click({ Invoke-Ui { Stop-Session 'Phone'; Stop-Session 'Camera'; Update-Controls } })
    $save.Add_Click({ Invoke-Ui { Sync-Settings; Save-Settings $script:Settings $preferencePath; $status.Text = $script:Strings.saved; Add-Journal $status.Text } })
    $clear.Add_Click({ $journal.Clear() })
    $logs.Add_Click({ Invoke-Ui {
        $folder = Join-Path $script:ProjectRoot 'logs'; [void][IO.Directory]::CreateDirectory($folder)
        Start-Process -FilePath 'explorer.exe' -ArgumentList (ConvertTo-NativeArgument $folder)
    } })
    $help.Add_Click({ Invoke-Ui {
        $file = switch ($script:Settings.language) { 'ru' { 'README.ru.md' } 'es' { 'README.es.md' } default { 'README.md' } }
        Start-Process -FilePath 'notepad.exe' -ArgumentList (ConvertTo-NativeArgument (Join-Path $script:ProjectRoot $file))
    } })
    $languageBox.Add_SelectedIndexChanged({ if (-not $script:Updating -and $languageBox.SelectedIndex -ge 0) {
        Invoke-Ui {
            $script:Settings.language = $languageCodes[$languageBox.SelectedIndex]; Update-Language
            Save-InterfacePreferences $script:Settings.language $spanish.Checked $preferencePath
        }
    } })
    $spanish.Add_CheckedChanged({ if (-not $script:Updating) { Invoke-Ui {
        $script:Settings.enableSpanish = $spanish.Checked; Update-Language
        Save-InterfacePreferences $script:Settings.language $spanish.Checked $preferencePath
    } } })
    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 250
    $timer.Add_Tick({ Invoke-Ui {
        Complete-UiWork; Poll-Logs
        foreach ($mode in @($script:Sessions.Keys)) {
            if ($script:Sessions[$mode].HasExited) {
                Add-Journal ($mode + ': ' + $script:Strings.ended + ' Exit: ' + $script:Sessions[$mode].ExitCode)
                $script:Sessions[$mode].Dispose(); $script:Sessions.Remove($mode); Update-Controls
            }
        }
    } })
    $form.Add_FormClosing({ param($sender, $eventArgs)
        if ($null -ne $script:PendingWork) { $eventArgs.Cancel = $true; $status.Text = $script:Strings.waitForOperation; return }
        try { Stop-Session 'Phone'; Stop-Session 'Camera' } catch { $eventArgs.Cancel = $true; $status.Text = $_.Exception.Message; Add-Journal $status.Text -ErrorEntry }
    })
    $form.Add_Shown({
        Add-Journal $script:Strings.ready
        if ($SmokeTest) {
            [void]$form.BeginInvoke([Action]{
                try {
                    $folder = Join-Path $script:ProjectRoot 'TestResults'; [void][IO.Directory]::CreateDirectory($folder)
                    if ($script:Settings.language -ne 'en' -or $languageBox.SelectedItem -ne 'English') { throw 'First launch did not default to English.' }
                    if (Test-Path -LiteralPath $preferencePath) { throw 'Initialization unexpectedly wrote language preferences.' }
                    Start-UiWork 'Discover'
                    if ($refresh.Enabled) { throw 'Busy state did not disable duplicate USB refresh.' }
                    $deadline = [DateTime]::UtcNow.AddSeconds(5)
                    while ($null -ne $script:PendingWork -and [DateTime]::UtcNow -lt $deadline) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 }
                    if ($null -ne $script:PendingWork -or $script:Devices.Count -ne 1) { throw 'Async discovery did not complete.' }
                    $deviceBox.SelectedIndex = 0
                    $fixture = Join-Path $script:ProjectRoot ('logs\ui-smoke-' + [guid]::NewGuid().ToString('N') + '.log')
                    try {
                        $feed.Attach($fixture, 'Phone')
                        [IO.File]::WriteAllText($fixture, "INFO: USB connected`nINFO: Texture: 640x1280`n", [Text.UTF8Encoding]::new($false))
                        Poll-Logs
                        if (-not $journal.Text.Contains('Texture: 640x1280')) { throw 'Process logs did not reach the embedded journal.' }
                        Start-UiWork 'Info'
                        $deadline = [DateTime]::UtcNow.AddSeconds(5)
                        while ($null -ne $script:PendingWork -and [DateTime]::UtcNow -lt $deadline) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 }
                        if (-not $journal.Text.Contains('Fixture USB disconnected')) { throw 'Async error did not reach the journal.' }
                        foreach ($language in @('ru', 'en', 'es')) {
                            if ($language -eq 'es') { $spanish.Checked = $true }
                            $languageBox.SelectedIndex = $languageCodes.IndexOf($language)
                            if ($phone.Text -ne (Get-Strings $language).phone) { throw "Language switch failed: $language" }
                            $restored = Read-Settings $preferencePath
                            if ($restored.language -ne $language -or $restored.serial -ne '') { throw 'Language was not saved independently of unsaved device selection.' }
                            $script:Settings = $restored; Update-Language
                            if ($languageBox.SelectedItem -ne @('English', 'Русский', 'Español')[$languageCodes.IndexOf($language)]) { throw 'Saved language was not restored to the UI.' }
                            $form.PerformLayout(); $form.Refresh()
                            $bitmap = New-Object Drawing.Bitmap($form.Width, $form.Height)
                            try { $form.DrawToBitmap($bitmap, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height))); $bitmap.Save((Join-Path $folder "ui-$language.png")) }
                            finally { $bitmap.Dispose() }
                        }
                        $form.ClientSize = New-Object Drawing.Size(1024, 700); $form.PerformLayout()
                        if ($journal.ClientSize.Height -lt 200) { throw 'Journal collapsed at minimum size.' }
                        if ($help.Right -gt $footer.ClientSize.Width) { throw 'Footer controls escaped the minimum width.' }
                        $tips.PerformClick(); $form.PerformLayout()
                        if (-not $helpCard.Panel.Visible -or -not $leftScroll.VerticalScroll.Visible) { throw 'Expanded connection guide is not scrollable at minimum size.' }
                        $bitmap = New-Object Drawing.Bitmap($form.Width, $form.Height)
                        try { $form.DrawToBitmap($bitmap, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height))); $bitmap.Save((Join-Path $folder 'ui-minimum.png')) }
                        finally { $bitmap.Dispose() }
                        $spanish.Checked = $false
                        $restored = Read-Settings $preferencePath
                        if ($script:Settings.language -ne 'en' -or $languageBox.Items.Count -ne 2 -or $restored.language -ne 'en' -or $restored.enableSpanish) { throw 'Removing optional Spanish did not save the English fallback.' }
                        Write-Host 'PASS UI: English default, RU/EN/ES autosave/reload, async discovery/error, embedded logs, minimum size.'
                    } finally { if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture } }
                } catch { $script:UiTestError = $_.Exception.Message }
                finally { $form.Close() }
            })
        } elseif (Test-Path -LiteralPath (Join-Path (Get-ToolDirectory) 'adb.exe')) { Start-UiWork 'Discover' }
        else { $status.Text = $script:Strings.setup; Add-Journal $status.Text -ErrorEntry }
    })
    Update-Language; $timer.Start()
    try { [void]$form.ShowDialog() }
    finally {
        $timer.Dispose(); $form.Dispose()
        if ($SmokeTest -and (Test-Path -LiteralPath $preferencePath)) { Remove-Item -LiteralPath $preferencePath }
    }
    if ($script:UiTestError) { throw $script:UiTestError }
}
