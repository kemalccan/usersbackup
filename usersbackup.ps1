# usersbackup v3.0.2 | Portable Windows user backup and restore
# Windows PowerShell 5.1, .NET Framework 4.7+, Windows 10/11.
# Runs as the currently signed-in identity. No elevation requested at launch.
# Execution policy and code-signing restrictions must be resolved by the system owner/IT; a .ps1 cannot override them.
# Requires no modules or companion files on the destination computer.
$ErrorActionPreference = 'Stop'
# Startup diagnostics: execution-policy/signature blocks happen before this script starts.
# Runtime errors after loading are captured here rather than silently closing the window.
trap {
    $detail = [string]$_ + [Environment]::NewLine + [string]$_.ScriptStackTrace
    $logFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'usersbackup_startup_error.txt')
    try { [System.IO.File]::WriteAllText($logFile, $detail, [System.Text.Encoding]::UTF8) } catch { }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [void][System.Windows.Forms.MessageBox]::Show(
            ('usersbackup başlatılamadı.' + [Environment]::NewLine + $detail +
             [Environment]::NewLine + [Environment]::NewLine + 'Hata kaydı: ' + $logFile),
            'usersbackup | Başlatma hatası',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    } catch { }
    Write-Error $detail -ErrorAction Continue
    break
}

$script:SourceScript = $PSCommandPath
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function UiColor([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
function UiFont([float]$size, [System.Drawing.FontStyle]$style = [System.Drawing.FontStyle]::Regular) {
    [System.Drawing.Font]::new('Segoe UI', $size, $style)
}
function Label([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [float]$size=9.5, [string]$color='#39465A') {
    $obj = New-Object System.Windows.Forms.Label
    $obj.Text=$text; $obj.Location=[System.Drawing.Point]::new($x,$y); $obj.Size=[System.Drawing.Size]::new($w,$h)
    $obj.Font=UiFont $size; $obj.ForeColor=UiColor $color; $obj.AutoEllipsis=$true
    return $obj
}
function Button([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [string]$bg='#E9EFF8', [string]$fg='#405775') {
    $obj=New-Object System.Windows.Forms.Button
    $obj.Text=$text; $obj.Location=[System.Drawing.Point]::new($x,$y); $obj.Size=[System.Drawing.Size]::new($w,$h)
    $obj.Font=UiFont 9.4; $obj.FlatStyle='Flat'; $obj.FlatAppearance.BorderSize=0
    $obj.BackColor=UiColor $bg; $obj.ForeColor=UiColor $fg
    $obj.Cursor=[System.Windows.Forms.Cursors]::Hand; $obj.UseVisualStyleBackColor=$false
    return $obj
}
function Card([int]$x,[int]$y,[int]$w,[int]$h) {
    $obj=New-Object System.Windows.Forms.Panel
    $obj.Location=[System.Drawing.Point]::new($x,$y); $obj.Size=[System.Drawing.Size]::new($w,$h)
    $obj.BackColor=UiColor '#FFFFFF'; $obj.BorderStyle='FixedSingle'
    return $obj
}
function Get-ActiveIdentity {
    $id=[System.Security.Principal.WindowsIdentity]::GetCurrent()
    $name=($id.Name -split '\\')[-1]
    if ($name -notmatch '^[a-zA-Z0-9_\.\-\p{L} ]+$' -or $name -match '^\.+$' -or $name.EndsWith('.')) {
        throw 'Oturum hesabı için geçerli bir klasör adı oluşturulamadı.'
    }
    if ([string]::IsNullOrWhiteSpace($name)) { throw 'Kullanıcı adı bulunamadı.' }
    return [pscustomobject]@{ Account=$id.Name; Username=$name; Sid=$id.User.Value }
}
function Get-UserFolder([string]$key) {
    $userProfilePath=[Environment]::GetFolderPath('UserProfile')
    switch ($key) {
        'Desktop' { return [Environment]::GetFolderPath('Desktop') }
        'Documents' { return [Environment]::GetFolderPath('MyDocuments') }
        'Pictures' { return [Environment]::GetFolderPath('MyPictures') }
        'Music' { return [Environment]::GetFolderPath('MyMusic') }
        'Videos' { return [Environment]::GetFolderPath('MyVideos') }
        'Downloads' {
            $keyPath='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
            $guid='{374DE290-123F-4565-9164-39C4925E467B}'
            try {
                $reg=(Get-ItemProperty -LiteralPath $keyPath -Name $guid -ErrorAction Stop).$guid
                if ($reg) { return [Environment]::ExpandEnvironmentVariables([string]$reg) }
            } catch { }
            return [System.IO.Path]::Combine($userProfilePath,'Downloads')
        }
    }
}
function PathWithin([string]$child,[string]$parent) {
    $c=[System.IO.Path]::GetFullPath($child).TrimEnd('\')
    $p=[System.IO.Path]::GetFullPath($parent).TrimEnd('\')
    return ($c.Equals($p,[StringComparison]::OrdinalIgnoreCase) -or $c.StartsWith($p+'\',[StringComparison]::OrdinalIgnoreCase))
}
function DisplaySize([long]$bytes) {
    if($bytes -ge 1GB){return ('{0:N2} GB' -f ($bytes/1GB))}
    if($bytes -ge 1MB){return ('{0:N1} MB' -f ($bytes/1MB))}
    if($bytes -ge 1KB){return ('{0:N0} KB' -f ($bytes/1KB))}
    return ('{0:N0} B' -f $bytes)
}
function Find-OwnDirectory {
    $exepath=[System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ([System.IO.Path]::GetFileName($exepath) -match '^(powershell|powershell_ise|pwsh)\.exe$' -and $script:SourceScript) {
        return [System.IO.Path]::GetDirectoryName($script:SourceScript)
    }
    return [System.IO.Path]::GetDirectoryName($exepath)
}
function Message([string]$text,[string]$title='usersbackup', [string]$kind='Information') {
    [System.Windows.Forms.MessageBox]::Show($text,$title,[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]$kind) | Out-Null
}

$script:Identity=Get-ActiveIdentity
$script:ProgramRoot=[System.IO.Path]::GetPathRoot((Find-OwnDirectory))
$script:Known=@{}
foreach($k in @('Desktop','Downloads','Documents','Pictures','Videos','Music')) { $script:Known[$k]=Get-UserFolder $k }
$script:LastReport=$null
$script:Busy=$false
$script:Worker=$null
$script:WorkerRS=$null
$script:Handle=$null
$script:Cancel=$null
$script:Queue=$null
$script:Finished=$null

$form=New-Object System.Windows.Forms.Form
$form.Text='usersbackup'
$form.ClientSize=[System.Drawing.Size]::new(980,790)
$form.FormBorderStyle='Sizable';$form.MaximizeBox=$true
$form.MinimumSize=[System.Drawing.Size]::new(820,690)
$form.StartPosition='CenterScreen';$form.BackColor=UiColor '#F3F6FA'
$form.Font=UiFont 9.3;$form.AutoScaleMode='Dpi'
# Window icon is embedded so usersbackup.ps1 also works as a single file.
try {
$script:IconStream=[System.IO.MemoryStream]::new([Convert]::FromBase64String('AAABAAcAEBAAAAAAIADRAgAAdgAAABgYAAAAACAATQQAAEcDAAAgIAAAAAAgAKQFAACUBwAAMDAAAAAAIACLCAAAOA0AAEBAAAAAACAAdAsAAMMVAACAgAAAAAAgAIgUAAA3IQAAAAAAAAAAIACWBwAAvzUAAIlQTkcNChoKAAAADUlIRFIAAAAQAAAAEAgGAAAAH/P/YQAAAphJREFUeJxdk8FrVFcUxn/nvHvfmzcziWM6WGNDmaIFFdEKCtpaKLiQNrgr1C7triv/ABcuXHVXqCtRN25cuHMjhZZuROiqrlSaVlQymkxqJplMZt689+7pYsaQ5FsduN+5h3M+fsI2rQ6sVQb25wUmINvfDMw7xCmdRir/AJiZODPTdptK3OAXg2/zwqbNBJNxl+j4JwGKEkTZWOnbA834EVhXEQlS40azyg/DEdOxF2op1CpQS0EFytIIAcpgZBn1D6p8P1DuiIjJm1VroTwTwUWKLLzuamdtgIuUEAJHWk2aDT+eLpDnWGkhqKiOCk44VQ6UkMQRdLpDfrr7mNXekNhH9Ddz5s8dYv6LFv2hgcG+mao0arFKhARjTl6sjM7UK/5xdyPj+u1HLL/rE/sIA0Iw8iKgAohQloFmo8rVy2dt7sOa9AdcUArwHl697fFqaR3vI8ygtznimzMfc+n8pwzzktgpacWz2OnxYnGNxEOWFaLvY1IRvFPMxodb2xjRbKTsn6my3h8hAmaGd4qqYO/7dmRtk7iC8eXxWSIVyhA4fXgfZbAtz3Y5dkkEhlnJ0dYMFz9vISK8Xt5gYXGdeup323HkOeAJkwkiwlTVc+/3BdLEkcQR9//4l6maZ3LLLS9gTqpeQ4DpegJAp7vJV6cO8clHe1jq5YBx6evjLC71+O3Pv3Gq7KknhADiiORl1w56wtMkVn30pK3PX76TtOJQEURksrcRzBgMCw7ONezcZ3MhBKKi5KQAtNfs3uw0360OMBdBsDEHWzhNapUxD3tTpN3l4c2fmZdr10yvXGGqjLmFhItmmuzkcCeSEHJV/XVUcHl2ihUxMxERA/gvs2NR4ECWQbELZweWJGAly3vr8tdkNfkfYvclfSLihj8AAAAASUVORK5CYIKJUE5HDQoaCgAAAA1JSERSAAAAGAAAABgIBgAAAOB3PfgAAAQUSURBVHicrZZNaFxVFMd/59733mRmMpOME5LY0hS01abFgmJpoeBKkUqliPiBqAvRqitduTQUXGl3IqI7USsUCoJULaVKQd1YP2gtsZK2NNLvtJ3JJJmP9+49Luajk87YWvC/eLx73rnnfz7uuedBC6oq/E9QVdN+D9rGRUT37lX78HaeQ9gWJ6zwHlBuTiyoMRBYLiMcPPEbn4pIdWpKza5d4kVVjYj4CxUdCwz78hm2JoDT2/PaCETAfI2ji3WenBiWGVU1oqrmOATFCoeLObbMlWkAVhVUfa/DYjAC3fxCZ+0KQ0TlBf6ar7NpbZFKICL+XFmfHsmz5XKZhgiRKqRTEAamx1A9hkYMckPiWkt7rURjdJh7fMJOEdkdtD7uiMGLYLwqgYXjp0tMn55rkmhTyTnlgXXjrBobJI4V6WJRba0FW/V4FR4HmgQoY04xXtEoEBD4YO8RZi9VSIVNAhGhWos5OnMn77y2FUGWRREGQj2GOEacxxgYUVVpRiB4FAIDS7WYzw9MU6k2GBkaWJaGXCbk7OUKb3/0UyfxIuC8MlrI8swjkwwPplAFbZWldUwRVYhC+PjL43z94wwjhQzOX69AM/8OX4P5hTm0qzrGCEemzzO/WOetFzYvcyoA8IAxsFCHU2dL5HNNL66fHGGpFvPy9vXkMiHv7zvGQBSiLSURCK1h9sI8laWYkYGwQx9wA6wVvFew12XGQOI8G+66g2IuRZx4UqHi2wSA94q1vT3ZQ6A3NJgAiWsmpFZ3VKOkpdfbiX1EmF7Rcjiv5DIhVgTnPdqSRaHta/CWEXTDGqGyFPPGUxsp5gdQbUaz66VNLNZi3vvid/LZqG80/ykCr8pgJuSTb08wWsiwaXKUydUF7p0osOfgDNl0eFPjfQm6m8d7iOOEvy9WeOXd7/jj1BynzpV5fff3nLlQJo6T5oHos7eNoMXS0XJOsUYQIAwNaybGiQJDteH47NAZrBFWjhdZs9rinGf2fIlGkmCN4Jz21KVdA+M8DESwaizHn2eukE0HZNMpHnpwDanQAoJvFTmwBu8VRdmz/xfKCzVqjYS1E0Xy2RDnwbTuv2Ynw1UraC2BFx+7D2MMZy/NI0b45vCxzlUprWenixWGshH5bMTIUJrnt20AUCOoKiUR0WaKDPtThh2lxPv8YGTffPZ+ao3+Oe0HVUiF4DzU6t4PZ41dFA4AyJSq2QkDdoGfhwZZf7VEA7wVMbc1o7UZlsvniRYXOe9g44ocVzoj82JJ7w4ivhpKM1n14BzLRtW/oqVjLKSb99nsUpUnVhbkV1U1gYj4qSk1Y8Ny8odp3Ty5mleBR5OEcedvMfABI6gIWMuVRDh06Rofrlspc23HOwbagq61iIje6nemrSMi2rW3Y+sfidnuK9s4qzoAAAAASUVORK5CYIKJUE5HDQoaCgAAAA1JSERSAAAAIAAAACAIBgAAAHN6evQAAAVrSURBVHicpZdLaFxVGMd/37ln7txJk0mmSVtTaxvwSUo12lKtUhciulAUVMSirgpd6M7HoitBV7p1oYLgyopBRGhFrIgPfNBqrAqtWpVEbUttYzLJJJnHved8Lu5MMkkmdmL+cOBy7rnn+3//73/PA5ZAVUVVg6X9a4WqBqpqlvbbJYOMiHjATav2+YShpMrmmvsfER2EEYhhXB0/iMjZJTGWMTQAP/6umyYq+sr4nP5TcqoVVS3/z1ZR1RlVHZ/T0kRZD53+W69sqNGIK82szo3rYLaD9ztzDEzNQhzjjbCc7SqgICYg6O6EcpWJ2RIPXrFBPm3ElOfqmR8osT5jGMnl2Do9TSyCFUkJrhWqKJBEERn1lFzMrg15fgVEVDUQEXeuqK/1dXPgYpHYGDILHyteWZmJgJH2eHpPUujBFosc3VyQu1XVCMCZKe01MBYErHMJNDJXhWwIGZs+L4stkDioVNPndsRAUBsgNcfg5Xn52QKIsqurk85SCS8G08g8Y4Vf/ijyybd/LA8gQuIct+7Ywg1Xb6BS862VWKyQ4HGdXdiJInuBlIAK/TZAJTWcUV3I6NV3v+O3M5NEocU3ySBA4jwjP53n5WfvojcfkLiFUmldIeehXE07RNJ+k77bDPV1wICnqcwiEIXCyM/jTM1UWZ/PYeofL0mOxHmOfj3KhkJEnCwwF8B7pbcnx44r+/AKrmk9sQY3T2BRkVQJM8IbR07y/he/EWXTIa6FB4wRAiO89dFJnNOWPlDg9qGtPPHQECJm3kvepwkvIuDU05kzHDt5gfc+O01+XRZt5b46ZuZivCpdHWFLhQBEhI+/GeW6gV7uuW0bpVlPWoR6EkvpGgOjZ4sEBswlnP3kAzs4+NhOQmuInU9/Wb+4qSphGDB6drLlHMs2h5R1699uKe7ctYW7d19Bxsp/jk9N3TqbZR5YDWbmYsJM0BbZlbBqAs2JNEzYeBaR//TMmgkIUKk5BMEGsohMqoYhClenSEsPtBwowlw14Y6btvD8/t1Ya0iS1HiJU55+ZIi91/dTrroV670mAkgqvw2EW7Zv4oX9uwkzAXHieWbfEPfdNkBH1qLaej1YCW2XwHulI8pw+MsxEuc5+NhOAJxX9my/jJcOneDwl6MU8hHet1+DthVoyNrbHfHh8b948c0TAARGeP3IKT449id9PblFY9tBWwqIQC1OqMUOEcgEwjuf/spkqcy6yHL4qzG6OkKmZiqogrWGKLRtmdECBE2rqJD+Uo1MGsGvHdjI3psGqMWKiGCMMFtOl+KnHt82v+plQ2Hk1DlGTp0hCm06R9NcTdB5Ah6C+UwTuP6qjQxnAsrVhGwY4L2SDS3ruzuo1BQjggKFfA6Q+Zp7r+QiIReF6dYtUIsd3is3XnsZbtGem8ZslGDceRAxUq0p12zt5skHd3Lo6ElmyzFRNsOPp89x4qezl3S4aqpgLptJjZu17LtrkN2DGylXwIhBQcVwsaE4Fy5ov8syKoZQPagiuSxMzTgmpsut5LskVNOtPd+Zpa87w1w1DabgoywmLnPjpoJ8v3AondK31+d5eKJILIaM94oNBFs/D672eDx/InIQJ4oxgipJVxd2usSxy7vZo/VTsQH0fJFtNuT7wNJdniMxBquNVNYEaeyuibUEQYDWquzp75Hjqho0rknSX5CxcpX7RZkq9GBVASUBWWMj8R7t6sJai5+d49F6cCMiC4e0xnVpbFwHJ6t65OKsuoqqVtfYKqo6UVGdrOjnZ/7RPc2xoGkhEhE3PKzBQJ+cAu4dr+hgucbNccyWJFnNppHCA9aCCBet5XghK98BDNc9t+KHqmpaXaPXClWV4eHl1/5/AZ2OKkw3EjtBAAAAAElFTkSuQmCCiVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAIUklEQVR4nM2aW4xdVRnHf9/al3OfM9OWttMZy6W8VAoEKQXRxOAVTfqkoPFBA1EevL1IiDHRiDeERF6UFI0JmHiJg5CaiMYEmCqgpjeQVigVKmA706EzZS5nzpyz917r82HPmUs7Z+YM53T0S/bTXuvb///6Luv71tpCC6KqAhhAWhnfAVHAiYi2p0VVBgfV7wymt/V9T1XNcmOaglNVT0QskIyoFk2N64xyjXNsTRyK67A1DBr6oI5R8XkuijkoIm+eg6U1Ao0JL57U9RvK3CXTfDLMcHHor40PxQrWMjZW1b0zFe4TkeMDqt6tS5A4D08D/H8m9GOFkJ/ks/RXahDVcYBbA/yoYoIAUyrATI1Kvc7XervlgYEB9W69dTEJWTwxBX9yVD/bVebhOIFajUQET2TNArhBQgHrefg9RRid5J4tZfn6ue4k8xPSF0PjenOxyB9nZrBJghjDskF0oUUVFSHZ0EUwMs6d/T3yw4UkzCx4Adz4uPb4hofiGP1/AA8ggqjin61gsxnuG6no1YAbGFAPZgnsA09EtCbcVS6xuVbDrgS+vQS9OhFBrEVzWYyNuVdE9JZbUgiiqiLACBTcJMeCkC1xhMLSBFQVEDzTGgnrFOlcAKnvk0SWq/q65JiqGh8wiFh7Vq8tlOibnsaJNAMPYZBCmZ6xiCwPSwSKeUM9Sue2jV6xpTzBWxN8CDgGGJ/ZQBZhV+ij1TRVnkcgBQ/Do9M89PsjDI9W8DxpbgYBa5Wd23v59Ee2I2I6QsKlDnA98CNgvkxQ2CogSrPNSkms8tO9z3P45RG6CiHOLY/IiPDIky9RLmb4+E3bmKoqxqzsTEZoZt1G/uxvgJojIELSTKG1Si4j1GNhaLRCuZhJY2AFMMYY8lmf14YnKGUFEcG0kNeiGOpRc7IKc/vAwlJiydHOKfmcMD4V8ew/TpFYBwquhT3ZOUfge5w6M8WevS8SJ9o0bgRwqvSUsuzcvpmtmwpUaoppYomlCCwBAPJZ4eiJs/z4kUOMjFUo5EJWiN05UYXANwydmeLEqfGWMpGiPDr4Mrfvvor37+xnupa6VDNZrholDIThsSr3/2o/U9WIcjGbWqAFEWFu9cLAIwy8FQkoqe/HseWB3x5iXTnHVZevZ6be1BLNNyunkAnhif1vMDYxQyEbrAp8nDjGKxHjlYiZeoKqYt3yj3OKtY7AN6iDx595BWH5CripBYxAksAbI+OEnlkx4ywEHyWOrRuL7Nq+CYBjb7zFkRNjZAKvpVTqVAkCw+mxClNVRxg0T8ErdluqqysbRIR6ZLm8r5vP734nAI/ue5UDL71JLvSxq9gMWhl6QdrFhgvZWavVoqTlwF+tXLB+VwS82fSxUsnRjvzPy+V2paMERGTZ1Rah467UMQLGCFFsiRK7ZAkgImm6tK3VQy1/tyNKjDBRibi0t4utG4tMV+M5/2+8j2JLPuNTyAVMVeOmG9Nqpe0gFoF6ZNlx2Tp+cMcN1GLL5+4dpFKL58ZEicMzhm/etouuXMD3f3GIE0OTy+b3VqVtCwipa6zrypLPBVzUneP+L72H/ouKc+Aygcf37rieKy7p4R2bimzozqWdWgf6tLYt4FTJZ33+8vwpvvEzx7du38W2vjKXbO6aqwF233gJ+axPPbLc/fABnj0yTLmYaXl3X046EgPOKT2lDM8eOc3dDx0giu1st6aoQj6brtN9v36Op18YpqeU7Qh46GAWSqzSUwp55oVh7n74IHHiEBF0thDZs/coTx46ybquTMtFYSvSNgFjZO5xCuvLWf56dJhv//wgUeIwIjz4u3/ym6deoaeUQXXxnHal7RiozkQs9gbFN4Yn9r/Ov4fGyWd8jpw4SyHrM1mpLyoMBchm/LZKjZYILKf+uh0XUyqEWDvfLippHVSLEpxTdvdvWkRSSRuUOLG8cHyIepS8bRILCSxaR6fg+9C7vsRBd5qCEZxNhxgRalHM5Vsv4oufumau5JZzlJnZbkSXcHmnkM/Cg494DO7/F8X8/CmHESGxjvXdOQo5Qz06r5eewzp/rCKLrWEE4hhu2rmVpw6+Ri1KyIY+ThUBMqHPyNgUe596lVIhg7W6ikIn1WGd4/hrI+QyAUIaG43mPrGOD19/WXr6cY5q1Xms/gKdZxYyExFqEWzrK/GFT7yLPY8eZnyqhucZVNMVqVRjfvmHwy2CXiwy+7Ew8PEX6HRO8TzDZz56JTdeuZlqjUXBbtJntKHG3zev8UDi0oJxbrCB6RnlvVf30r/xfTz9/ElOj1UwInNM261pdPYioLHy3aUs796xhR3b1lGtne86fnrdeKCBOj3cFdFTk7rBg+PGozuJ0xPhxiznlEwohEFr50HtiDGQWJipLVm1ujBEojo39HbL/gFVzxcRHVT1+0RGh8Z1b3eJ28bGSWRBTKTVpFKL1uieVTgPvCq2WMBUpjncW+aAqhoRsZK+VAPoyASX+gFHHYRxhDFmba+VlhOFpKuEPzHJzX3d8qfGLY0BEBEHmM3dcqJW56s9eTxjSFTX9B6jqagSbezCn5hgz0LwsKCUEBE7OKh+/zrZc2aSezZ0EYiAc1jW9kJmIXALJBvLhKMVHtvSzVdU1WPBbel5LtK4yhya0DuzIfeEWfypSVAlkbTAXAu3UhSvUEI8gWqVPfuKfPmWWeALf0FYEkzDRK+f0Wvzeb6D8sFSgcAB9gLbwgh4wHQNgL9HEd/tLcvjsxeRi8A3JQCLr/fHpvQKNXzAwbVAfxJ3pJk654MQBigwaoTnFP68Pi9/m8ViBJTV/vyhqmalny0upKiqDKQ+37Yio6r+oKqvqmZgIP2LpJPPAp2ept9pCfh/AU8jPJW4RfquAAAAAElFTkSuQmCCiVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAALO0lEQVR4nO2ba4xc51nHf897LjOzMzsz2XXcNVmvE+I4aUncBhI1IUEqEpAIFQGNVBBS1VIUEP5CEZ+CSj4QCrRUbShQlSgIIRFoHVIBEhBTyk0NcWLnIsetk7S2SbyJ17fd2d25nsv78OGc2fWsZ3fPeHd2E5W/9Eqe9TnveZ7/+9zeG3yfQwZ9QVUlfc8AmrbtRFceBayIDEceVRVVdYfS+SZCVV1VNVmfz6SQqjoiEgPRwYPq/NTP8SNRyN0qvF+UPUEIXIU1bRDqehBHzIvwgiMcps3zIrK4QuY1sa7Q3Y5OzmplbIQHw5iPuQ77C7nE5mJdtr+tRPebRsABghjabaZ9j6/WF3h88lp5LbUEXcstViWg6+siYs8u6kfzLo8U8+xrBNBqJbqnQmz1yPeDAsb3MaMFaHSYjyI+v7MkvwegqkZEbL8X+wrfo/yCfrE0wqeiGJpNIhGMCJl9bCuhiqoSuy5utQSLLQ7NXOSXbp2S2dVIuIKAVHlHRKKz8/rYtWUePD9PjCJi3pmKr4QqCkTjFbzFFkeaAffvrjAHsNId+ilkRCSantUvpsqHgPNuUR5ABBHBu1gjLBa404N/ItHVpAO8hB6lugHvzJw+UK3wqYuLhIAr7wQvvwoYgzc3TzhW4a635vh8mhV6dF5Srev3Z+ap5hyO+j7XN5uoeReNfD+ooo6DdR3oBNy9q8JR0vgGvWw4ImJd4ZPXlLih2SR+tysPiTvEMZov4Kjld9MYsDTwPRbwXfBL87xQKPC+VgsdJNpb1SQZDeguZmv8S0XAdWm1Q26frMjr3azgwnKefLuht+UL/NAgymsaUws5wcjgBVEngNjqsIkQa4lKBUaCkA8DXyCxftsthQ1gxXJ3wYd2i5gMZbIquC44Aq/+b412J0KysNAt4wT27R6jkBNaQVLVDRESg4pyDwkBCstKJiLH3KkZh1AVXAfqzYCvfP0lXnrtXGINWepi6fah7H5PmQMP/DB7Jyu0gqFaggQBosqtb76pBaCtqtI1867I18c9Iq4ORfE9+JtDJ/jWy9MUci6FnEved8nn1ml+0op5j9Nv1/jyUy/R6sQ4ZtmlhgAJQxDDBGUK3YKotw6AMEtPqonZX6gFvPz6DNXRPFYVm9aiWVtslUoxz5lzC7z2Rg3fA6t2oD6sTVomBpJhjfQyG13p5xlmh0kbGREUHxHBqmKuck5kVRHA9wz5nGBVsscCBcdJ/tlsJ31lcKGeBwZa4ND0g54LL5y4wJHvzNDuRBgjV226qornGZ54+jj/8N8esV0aqTUhJNljrFzg1ht3cNet15H3hHYAZoDqJTMBifJKFMf8xT9+m288dxqAkby34fmwEeF703PEVgfrS0Ct8o3nT7N/7xsceOB2do6N0AmzZ5QBLEDxHPizJ4/xzSOnGa8UgGQUNgM5301GftDuJCHw+MkL/MFfHeaRX7uXkbxHFEsmS8pkLNYqxYLwzaNv8Z8vvsGO6gix1Q0pb0QwZrktBTQdsFklii2VUo43Z+b566dP4HuCZmQyEwEiEMfwzLEz+K7JHHXXQqsTUW+F1FshjVa44SW12FpGCh4vvTbDxVqA52SLS9mqPUeo1UPOXqzjuk5mdvuhG7zee/01lApeKrzy6htzRLFmMtvV5HSMYaER8Nb5OuP7xghjRdaJKgMFwc0YeREhiGIO/Pxt3DJVBSCKLR975N+oNQLcDWSURM7ENbJi29b5O0G0JGizE23b7sq2ESDp6ips2ZS4L971Cx4bxf8TsN0CbDe+7wnYkiC4HOPWD3YiSYDcjJSbBUO3ACNCFCtBaAnCGLPGLMWIEMfKYjMAss0KNyzfUDs3QqMTUsy7fObBD7L/xnFq9Q5uHxKMEZqdiLFynl/+6fcSRJZOGCNDZmFoLiACYWS5bkeRhz9+J3snK+ybqvLw489z+DvncC4jwRihHcSUix4Pf+IObpqsctsNYzz6d8c4N9fKXNdfDYZmAYIQxZZqKcfUxCjWKuURn9//1bvY/4Nj1FvLq29haBkd8fjcr/8oN01Wia2yf+8OKkUfG9t16/mNYGgEWFUKOZdXTl3it/70GVpBlCyl5V3+6MA97JkY7Xn2dz5+BzfvrqIK7U7Eb3zpW7xy6hL5nDtQbT8ohhoDrFXKRZ9XTl3ioT8/TLOTjHql5DMxNrL03DWjOfZeVyG2Sr0V8tBjhzl+6hLloj/0bDD0LBDHSrXkc+xkQkIjNf3LF1NUk9+OEf7wiRd5+bsXqZZyxPHwU+GWFELR5SQ8lpDgmCTXd5e3HSN86alj/M/xs4yVc0Rx3xMtm44tqwRXklBvhRiTnGQwqfJP/sdJyiM+0RaMfBdDIUBI1/xWtNgm/n789Cyffvw5ps/XqdU7PPrkMb7+X6fYUcmj2v/dYdUDA9UBWUQQSfw5CKJVn/cc4YVXz/Mrn/13fNcwu9ihVPCopxXgSijgOgbPddAMGWEQqgZbElvn4yIQRZaRgs++PTuI49XL2cQiEv+/cY2F1u4m7IVaiwuzi/ieuyYJ3YCaFesSIAJWoZA3jBZzLDaCZGNw5XNdYV2HT/zsB9m3p5ptg2KdvQAFHAOLjYAvf/UZzs3WV7UEVSWfc6iM5rG22/naWElAX1HiWBktOuybGuPU9Bz5XL5vlFZVfNdhvFpMttDYeJDp7rhXyz4jhaQu6MeZMUK7EzE1UWH3ziJBuOo+Yc+rPQTIKhYhIgQhfPieG3nu+Ns02yH5nNOTpxUwxtBoB/zl3x/mtpsmCCPdcPBSVTxXODOzwKnpS+T8KytDYwRNN0g+8qGbyflCo6Wr7RE6cplpdBWWVInZfuKKQDtQpiaKHHjgdv74a0epN0IKeRcj0kNpzneZnqlx6sylTZvOJm5gyOdcVFkiVUjiUrsTEcWWX/jJ93HvByaoN7XvtDslZKERLh8DSBRXdUUkequmvz1e4TOz80QiV1pDbJVSQfje9AJPPP1tTk7XaLbDK/y4u6ix2egJlJL6vO8yMV7kIx+6mXs/sIt6q7/pqxKPlnHqixzaVZH7ew5JdcV3HJ7rJEdE+hqPYxLTuuEHynz6k3dz9mKL87ONbOeCNhnddFsp5di9c5Scz6ojn0K95L+OpL97DklZgEbIUbWc9X0mggCVPvPQZO6ebDm9Z7zA5M7Ctm1qJNtsEISkPr+61YlgWgFxDP+c/km7fSS/lt3gC9dW+M0LNSJj1k6TyWmRbTwwr9ncTZW4VMKp13lxV4U7WOWkqFVVUeEriy0WPA+j6+yCiiQW0a903ZJmspXIIqgRsPC5lSdFzfJDYgEzWZHX220+WyligGjd3t/hsJaoXMatLfCvk1X5Whr8lq7S9Lsv4AA6s8ChsTI/cbFGaAzelkq9SbCWuFjECUPO15X3X1/kPCwNNtA/2ltAY/jFxQZHxqp4qoTrucM7DdYSFYs4Nmau1eJnbijJDPQqD30I6PrIZEUuNSLuazR5ZqyCJ5IwyvbfE1wTqsSqxNUqrrWcrde5b2qHPJ/ehbiifu+b70XEqqrZU5W5p07w44sNHs35xNUqDoKoEqUfGvRs5KY3kmIwViWyFi2N4oyWcVot/uXcOe6YulaOrHWFbs0QqqpijKgqzMzrXbk8DwUB91VK5CIgDCCMtvfamDGQy4Er0GiDEZ4NQ/5k56j8barDqjfGIJPsKgcV89GUwQsLeovrc38Y8WMIt2DZFdltuDVJcmjTxtRFOOE4PGuEQ+Mj8iws3YC54pLUSmSWu3sd9XI204wxWqvBwjB3L/qgrKhUkQq0RaR1mUzpitz6t0avCqpq0vu5zlA+cBXoynTw4OAybWjUVl5B2y5s5Mb4/wFilhdSyv6APgAAAABJRU5ErkJggolQTkcNChoKAAAADUlIRFIAAACAAAAAgAgGAAAAwz5hywAAFE9JREFUeJztnWtwHNWVx3/n3u55SBpJlmzzMDEvQ2AJFbBlY2o3gMkTHB4hBZtUUrV5kt2E7JewW2STrZBUkq0k+6qtpLZIUhs2yW4Sex9gAgRXQTBkCxwkSAIEMI8Y8zDIlqyRRqOZ6e579kPPGGMkW4+Z0UjqX5U+aNSa6enz73PPPef0vZCQkJCQkJCwFJH5+FBVFYCBATzWzccZtAgDsC7+/q76g4jofJ5SQ1BV2aJqVdWf73NpdVTV6+9Xv3aTNBqvkW+uqnIvWBEJgaj6g6p2vjSKb4VrrSEVho08i9bFgOvuwuTzPGBDHgQQkdHa30XAObWAa5RnaIjKtqjaqw856cde1Y6eDG/r6WTDgTznZdP8cbECPZ10mkacwAJBAQsMj4NTRtVRsYbvRRFjx3bxfRHZd/BYVQ+I6i2EugpAVWUAvD6RoPr78r15PmMt1xnD8mVtUIxgohSrOwwIBRQhvhpLDQFVEMG3Nr4mXW2xmyyXGDWGB8Ym+KfxkAdOXx57BlW1IhLV8RTqg6oaEXEAL43oOzvb+FwUcX4qQ2dxAioVAAIBo2AAROYnCG1FVONbQIRQFTEWr6MdSiWIIvYZ+NdP38lXtl4jkapKvTxBXQzQ369+X58EO1/U3tU5PivCFztz2NExUEeoYBNjzxhVxQHG85Dl7VCosN05/qE7K9tV1QAyV28wJ6NUI1UREffCsG7ubOOHqTQ9+TGIIiJjMHP9jITYOyiEuQ58AxQnuO0zd/K+qjeY05Aw6xis6vL13nsx+8b0Rt/jFgc9B/IEzqHGYEmMXxdEECP4hQLRaIEo18FlP7iSO5/fr+8Qkai/f/bT61kZSFXNjcBZIBcWuHVlB5tfGcU5hxiTGL3RqBJ2duIFZVyhyGVv6pU7+lX9WvA9E2bsAQ4afyuyqcCtyzrYvDdPWRWTGL85iOCN5gnDCDra2PbCkF7aJxL0zyLRNiMBVKNPdxbIpku4tauDzfvzBCKkJTF9UxGDVwkgjJCONrbtHtTNfSLBFlU7o/eZ7oG1Of4qSMkYP+vJHTR+kt6dR5zDpXzwDFoKuOLYTu5kBrODaXuAWoInOsD1x8TGLyfGn3+MwVQCcIK1hi0DL5MRkehL8TTx6P8/nYO2qNo+keDFYX1vro3r9xUIgNSczjyhbhiDKZeI0ikyb8rxs72q7WdtRaZTUDqqAFRV2Ap7RrTH9/iZg44wShI7rYYY7PgE0coc73Wj/NXVV+MGplHsO6oABsC75hqJcFzX1U52okQgMvv8QUJD8fYXiXzDZ1+G7DoIjzYUHPEurmWZXhrVP8ml+EUpIBNGmOTub2GUqKMdO1pg26plcsWhNZrJOKI6tgKPPaYpo3zNS9EehEkBp+WReCjoznH5SyP6LhFxeoSp4ZRjRHXOH72Y126BjaPjaDW3n9DiqMP5FgO8B9g+EN/ok04Lj2RQq6rWKNd1dWA1IiLJ7S8IFLx8EbHw4ZdHdUWfSDDVjGBSAVTv/vDe2ODXFStYjZtXEhYAIkgYEPR2sUKVD0EczE927KQC2Fp9/c2jvLMtQ2dQwSVj/8JCwUwEYODSParZ58BN5gUmVcUfxXd7hLIhlyY1UaKCNCfx46rF72ZhRFikdQxTCkAdF44+TnTNW+JOosMPeoMAqgeFu1TTkue88biVq+Hu3zlFRGhLCymfpohAifsTK6FizeJTgYtwbRkiPYFNwF1bJwkGJ/UAIuKe2KcpfN5RCmJ30sjLEzmlPRPfib9+fJBde4ZJ+RZtoAoU8KzhorUnckyvT2EC1LFovIEI4iLCXI5sscRFwF2nTFcAAFIhLSmKInQ18kSdKp1twm+f2c///vJpfvfsPiqVEBFpeKOwAHc9+BxvX38Sl7/tNHxPqOY6FgUiECqIIaxWc994zOEv1DpLXhrRz/d28bUDeUIaVPVzCtkUDDw5yLd+vJMwdLRnfcRIc8YAIIwcB8bKXHjum/jLP12HGIPq4oh4VdFUCgkq7B8JOOXMFTJ2eEfxlB7ACBnTwHl/7IJhpBDw7f8awAjk2nxCpxA1Lwo0Ihzb08aOR17gpOO6+fAlpzNSWDwxgSogZOwUmp4yEVRtSW4YzinZNGzf+QfyhTIp38bGbzIKBKFjWS7N3f27eWWogu81fvhpMrOrBTQKBXxPGM6H3NO/m0zKw82D8Q89H88aXh0e596H99CWYV7Pp5nMa25fFcJIW2q8DcOopc6n0TT06eCj4VRbMuKOIiVqogcwIiDzU2hpugCcU8QIxkA25cVfvkVQhXTKozMtIIJtgn+sJaMOesMmZyabJoDarK6jTZgoQ6kc8PhzwxQmKhgz/0GXUyWdsjz6zCA3E1GqNDj7RS0WMlxwzmpSvmVZp6VUhiDSpt0YTRFA5BRrhbQHjzw1yC07nmX33hGC0EH8ePS8C0AVMinLo8/u46EnXmnaXWgEbv/VM3ie4eK+k3jXeSfTnfMZLyleE6aiDReAU+jICmGo/P1/9PPgoy9jDPi+xYhgW+Dur1EbArLp5o6ME+UQLSk/3f57fvHAs3z6/eu4cO1Khseq6wc08LMb+k2dKikPHn1miK337OJ3Tw+Sa4+LirVpVqsYv4aqNjMPBYAxgojQ5VuKpYB/2dLP7r1rePfGU+KaCI3LTDZMAE4h7QulcsQ3f/wQhWKZrvbUvCR7FgKqEKqS8j0EuOmW3wDCn20+jcGRxg0HDYlzFTBGqQQR3976MOVKQGdbYvzpoKooyvG9HWy7/2l2PDxIe1po1KVriACcU3JZYdt9z7LjkT1kUl5i/BkQz5jiG+g7/z3ASCHAs40ZLusugFqa95WhCnf372ZZLr1k0qr1xFVnJflCme07/0A23Zj0dN0F4JzSnoEdD+/h1eFxPGtaLtBbKDinZHyPe/p3c2A0akiRqiFBoGo8tWmdHN9rGBFkKtkrTU0BTwcjcbWyEkRk0/XvzKurAGrufygfcv9vXyCb8VvK/YvEwiwF0aRLEwqQa0u1TH1CAc8zDI+WuO+RPVzzzjXk69yr0DAPELRYVS02fsT6M1Zw9im9uEMaHeOeCQgixy33/YFy9QHIVkFVG3Y9G5YHkBa6gBAnW0qViL4zVvL+C0+d8rg7Hng+9hCmaV1p06JR13Ney8HNpjYERJESRXF9Ag4u10qxEraU0ZvBkhIAxEFgzfCHC2Cx9AHOhORp3yVOIoAlTiKAJU4igCVOIoAlTiKAJU4igCVOIoAlTiKAJU4igCVOIoAlTiKAJU4igCXOohOAVBc0rHf5fLEuJ7eoBGBEqAQRQeSIXP0esLRGKJZDoupSdouJRSMAzxOGR0tsWruKr3x8A5FTgshh5ljj96wwUqiw/syVtGd9KkGEZxePCBaFADxPGMqXeXvfCVz/gXPYcOYxfPUT5+GcEs5BBJ4nDI2WueCc4/m7azdyw4fWogqjxeBgM8lCZ8ELwBjYN1Li4nNX8aWPrscaQxA51p+xkq9dex5RVBXBDF23Zw1D+TIXn7uKL39sPU5h3ekr+Nanz2fd6Ss4MFZeFDHBghaACJQrjveefyJ/+5G+g8/Q+tYQRUrfm18TQTSDRRd8Kwzlq6L62Hqk+s7OKW9ds5xv/Pn5XLJhNZXALXgRLGgB1Po337NhNV7V6DWDWCuvF4FzRNMYDqyN3f7Fa18zPsRiM0aoBPF7vOe81a87h4XKghaAEBvshpsepP/JQTwvNnqNQ0Xw1U9uJHRKJZx6+UPPCPlChU3V4eRQ40O8eFTKN/Q/OcgNNz2InWr1xQXEghaAamw0Y4UvfG8n/U8NHjR6jdrv5562nK9fu5GUV/3Kk1hurBiw/syVfPnjGw4ecKjxrRX6nxrkC9/bibGCZ2TBt5EvaAFA/BStbw3WCl/47tQicKpcvHYV12xaE782yVCQ8i0fueTMeNmaQ5awe53xv7sTawXfmoY9s99MFrwAIA7OvKOIwEhs1MligJqhc20+Jx+Xqy5wEb84mfE9a1rqmce5sCgEANMTwXSyeKqvrVzqqqubDSxS48MiEgBMTwRHoyaSKIq9xe93D/P5asC32IwPi0wAUB8RqMZDgFPlB7c/SegU31t8xodFKACYmwhqUb2ifPnfHuKhpwbJtfkzEtBCYlEKAGYngsONf88jL9HdkVq0xodFLACYmQgmM35vV5pwERsfFrkAYGoRBKE7aPTaukBvMH64uI0PS0AA8EYRPPTkIL5nXqsbmHix/qVmfFhCC0TURKDq+MrND/HBd5zOpRtPxLPCrhdG+OndT/PrJwbp7Vw6xoclJACoiUBwDm669XH+Z8ezGCOMFQPKlShey3iRj/mHs6AEICKYOewtUFsazrNCT2eGUiXeRDPlWTIpG+9rUIfl6xdSvmDBCMAYoVQOqQRR3ZowDr6P1reu356N1xpcCJXChgmgnvv+igiFYpmzTzueNat7qASttdNYDZF4RnFf/7NUwgjfM3UTQaP2UW6IAETA9yxFwrq8VyUIOefNq/jY+9aTSbduDV4VUj6sPnYZP/p5f7wrWh3eV0TwPduQ7qO6CkCAIFR6uzze9tY3sfXuJ+jqSM9p/d0oUtoyKT5wyVpAyI+5lu7Nd05Z/5aVPL/3FO64/wly7bNfLV2AMHT0dGa44NzVTJSYc5v74TTMA2TTXt0U63kGz1qCSLHV1cdbVQLx9m+QTft1cdtO453F4q1j6k/dE0HGCOMluHDtao7paSeM3JyMZYwwPlHh6T376GiLe/CsidvBW+5HIJ0SyhXl6ef3kfK9OYnAGKEUhFzcdxLLOi1BWP/Yp+4eoDYMHNub4u19J/HvdzzKiu7s3JZhV7j51p0IG1hzYi+Vifo/+1cvjHH85I7f8ujTe+loS+NmKQAjUKpEdHWkedd5JzNRrr/7hyMLYLbnHidXJpTLLziV3XvzPPzUXrJz2DYmLuDAzdseoj3jt3QvnnNKsVShfQ7Gj8UtpHzLZ96/ju4On4m5bWQ5ZSv01AIQ2j15bR3dmRA/RCGkfct1V6/lL765ndFiedYbR6nGIlCF8Ylgxv/fVIQ5uf7a080vDxX41JXncuHalXPaNay672C7NZOPHm+IAZ6rqkWVe8ZKlK2HUZ15/GEEyoGSThn++sPrOXvNSvLj8Taxs3Fltetpq//fsj/V5tOZIhK3uFeCEAU+deU5vHvjyQyPzn6DCAGXSYHCPdF+SqpqREQPO+bwC60iItrfr/5xpzKUSpMLKqjM8hkIp9CegTBU/vEnk+wcaltsYf55IC5NK6VKRHcuXb+dQ5VgRRf+vjFuOK5TvtGv6veJvM6FTjkELDuFNiuURcnN9vMh9gSFibi79voPred3z8R7Bz+/d4RyEDE8OoGV1tk+ttkYgZ7OLJ5nuPKQvYNrbn8uYZ8IhA5VN7WdJ33/flV/HYR7R/j68m5uGMoTIPhzOJeDN3l7FkplKAcBu/aM8MTuIdK+bViqs5Vp5O7hqqjnIc5RiODkVZ2yv+bdDz1uamWI6N4RHVGI6rG7d+37FIpxu3U65bP2jBWcf/aKJT0CKDBRim+QsXGtVjzrM90TAecoHihTmvKYSU+qqpRn9urKjjZeEIMfOZA6J+Cc6pI2fg0jUv+LqwS9XXhDef752C4+NwDe4eM/TOEBRES3qNoRONCe58FclgvyY0QY6rpxXe2LJ9QfMZhygDj4hYioqk6aC5gyFXw10CcSOMMXo4iKqf+ehQkNQpWoPYvNF9i+qlu2b1G1IhJNduyRagEOVTmQY2ehyKi1s8sHJMwLLuWhnuVOVZVTjmDnKf8gItoP3lkQWo/v9LYhaB0K/AmNRXEpH+/AKBOFIv8JsI6p7XbEauA6CLeCuA6+NTjK/bl2rDomdSUJLYKgnkXCiA+uOU4Gt8Ibsn+HckQBiIiuADlOZNxFfNFajLFTFxYS5hdVws4O7HiJHSf0yLYtqvaaKcb+GtOKwbUaRLx0QLf1dnPZ0AiRqfOMIGFuqKK+R5TyoFDh4uNz/B8gUwV/NabbEOJ+qert6uaqfIH7uzqw6pJ4oJUwhjCbwds/xlWrOuV+pmF8mKYAamPIJpGwFPA3UUTkexjnkuGgFVAl6M3h58e47dQVcpuqetMxPsygJWyTSKiq9sQe+dX+Ua7wPDTlQyKC+UWVYHkX/nCB23f9hqt+qerB9AP1GfUEikjU36/+qSvl9kKRyz2biGA+qRk/X+D2HXdyxb0X4S6C6EhR/+HMKhFbqyvvHtTNXTludYotl4kkCQybQrV+Ei3vwh6oGv/xq9EbARGZ0c0460x8TQQvDOmlne38SA09xSIB4M22eSTh6KgSWoNpy2ImStz2eD9X3XsR7kZmbnyYYymmNj18bI/2LO/mh8fk2DxYgCgiEkm8QT1RjVsmuruQSolIDVf2ZOTnqmoAnYnbP5Q5PRcgIpGq2resluEnBrhyaJwbgaGODqxT1DnCpH4wN1SJVAlSPtKeQVzIXaMVLqkZX0TcbI0PdSrGHtpp8mJeez3hBx1tXOZbyI9DGBJWP8tUO56TIWIKajeMxpG8zeWQlIFSiSEnfLQnI7fFx01d4ZsJdXkwpFpvlgHwThAZAi4fKui7bZYLXMgnl3exouRgYgJcFEevVBf7rsfnLwKcxP2z4nl4ItDVhlcKoFjkrqJy38gY3z1jVdzWtXUrph7Ghwa0Yxzed7ZrVFd0wScULsr4bCwFdC7PxfIenQB1rfuUTzNwCtksZEzcjz9SoOAiistyfL9cYUd3VrbXjq25/Hp+fsMuvapa4nRkeMhrnYN5NnZ1cf7QCL4RPiWWlHNLtjHIZVOYYoUHPMsDzhFGcJM3QemYY6QA8Q1F7ClnNL+fLg2/7qoqAwN4fX1v7Ed79VXtsBYz3OiTaFGWKbp8OSIio4f/TeOMntbL1c8/qqLxj1VVv/oFE6r0V69J9Ro1zSHOq+dt5hdtZRrh2hMSEhISEo7C/wMYfaGT1tLm/gAAAABJRU5ErkJggolQTkcNChoKAAAADUlIRFIAAAEAAAABAAgGAAAAXHKoZgAAB11JREFUeJzt3T161FYYhmE5Fz01a4Jl0KamIGVSUKdlGbAmalZACjIXZrCxRzpH5/u57z6xRtb7jDQGs20AAAAAAAAAAAAAAABACnerD2CVL1+/fVt9DMTy6uVduz20eMHGzl7Vo1DyxRk8s1QLQpkXY/ScrUIM0r8Aw2e1zCFIeeBGT1TZYpDqYA2fLLKE4I/VB/Bcxk8mWa7X8JXKciLhMZHvBsIemOFTTcQQhHwEMH4qinhdhwtAxJMEo0S7vsPckkQ7MTBbhEeCEHcAxk9HEa775QGIcBJgldXX/9IArH7xEMHKHSwLgPHDD6v2sCQAxg+/WrGL0wNg/PC4s/dxagCMH5525k5OC4Dxw/OdtZdTAmD8cLszdrP8zwEA60wPgHd/2G/2fqYGwPjhuJk7mhYA44dxZu3JZwDQ2JQAePeH8Wbsyh0ANDY8AN79YZ7R+xoaAOOH+UbuzCMANDYsAN794Tyj9uYOABoTAGhsSADc/sP5RuzOHQA0djgA3v1hnaP7cwcAjQkANHYoAG7/Yb0jO3QHAI0JADQmANDY7gB4/oc49u7RHQA09mL1AWTw9p/Pqw9hmo/vX68+BBa62/sfdngEqDz8a0KQ36uXdzfvWQAe0Gn414Qgrz0B2PUZgPHX1f31Z7Znlz4EvMfF/53z0IcA/M9F/zPnowcBgMYEYPNu9xjnpT4BgMbaB8C73O85P7W1DwB0JgDQmABAYwIAjQkANCYA0JgAQGMCAI3t+n0AVf46sD/kwkWV34Nw6+8EaBUAg+e5sgZBAB5g+OyVLQQCcI/hM0qWENwagLIfAho/I1W9nkoGoOo3i7UqXlelHgEqfoOIKeojQdtHAOPnTFWutzIBAG5XIgBVakwuFa679AGo8E0gr+zXX+oAZD/51JD5OkwdAOCYtAHIXF3qyXo9pg0AcFzKAGStLbVlvC5TBgAYQwCgMQGAxtIFIONzFn1kuz7TBQAYRwCgsRerD4D5Pn3Y/3fX37zLdUvLbdwBQGMCAI0JADQmANCYAEBjAgCNCQA0JgDQmABAYwIAjQkANCYA0JgAQGMCAI0JADQmANCYAEBjAgCNCQA0JgDQmABAYwIAjQkANCYA0JgAQGMCAI0JADQmANCYAEBjAgCNCQA0JgDQmABAYwIAjQkANCYA0JgAJPHpw+vVh0BBApDAZfxZIpDlOBGA8K7HFH1c2WLVnQAE9tiIoo4rW6wQgLCeGk+0cWWLFd8JQEDPHU2UcT0nVlGOlZ8JQDC3DmX1sG75+quPlV8JQCB7B7JqWHu+rgjEIgBBHB3G2cM68vVEIA4BCOLNu8+H/x9nDevo1xnxWhlDAALJEAHjr0UAgokcAeOvRwACihgB469JAIKKFAHjr0sAAosUgb2MPzYBCG71gI4EZPWx8zQBSCDjkDIec0cCkESmQWU61u4EIJEMw8pwjPwgAMlEHljkY+NhApBQxKFFPCaeJgBJRRpcpGPhNgKQmOFxlAAktzoCq78+xwhAAatGaPz5CUARZ4/R+GsQgELOGqXx1yEAxcwep/HXIgAFzRqp8dcjAEWNHqvx1yQAhY0arfHXJQDFHR2v8dcmAA3sHbHx1ycATdw6ZuPvQQAaee6ojb+PF6sPgHNdxv3Q7/oz/H4EoCljZ9s8AkBrAgCNCQA0JgDQmABAYwIAjfkx4ER//7n2H+as5K9//dhyBncAkxj/WM7nHAIwgYt1Dud1vHQB+Pg+9kXgIp0r+vmNfn1eSxcAYBwBgMYEABpLGYBsz1n0kPG6TBmAyPy8ei7nd6y0AYhcWxfpHJHPa+Tr8XfSBiC6yBdrRs7nHHd7/qMvX799G30ge739x4XBWpHe/V+9vLtp0+nvACKdfPrJfv2lD8C25f8mkFOF665EAIB9ygSgQo3Jo8r1tutDwG2L9UHgNR8MMkvk4d/6AeC2FboDuC/yN4m8Kl5XJQOwbTW/WaxT9Xoq+QhwzSMBe2Ua/p5HgBYBuBACnivT8C9ODcC25YzAfYLARcbB37dn/NvWPABQxd4AlP0QEHiaAEBjhwKw97YDGOfIDt0BQGMCAI0dDoDHAFjn6P7cAUBjQwLgLgDON2J37gCgMQGAxoYFwGMAnGfU3twBQGNDA+AuAOYbubPhdwAiAPOM3pdHAGhsSgDcBcB4M3blDgAamxYAdwEwzqw9Tb0DEAE4buaOpj8CiADsN3s/PgOAxk4JgLsAuN0ZuzntDkAE4PnO2supjwAiAE87cyenfwYgAvC4s/ex5ENAEYBfrdjFsp8CiAD8sGoPS38MKAKwdgfL/xyACNDZ6ut/eQC2bf1JgBUiXPfLD+Caf3Kc6iIM/yLEHcB9kU4OjBbt+g4XgG2Ld5JghIjXdbgDuuaRgOwiDv8i7IFdEwKyiTz8i5CPAA/JcDLhIsv1muIgr7kbIKosw79IdbAPEQNWyzb6+9Ie+DUh4GyZh3+R/gU8RAyYpcLo7yv1Yh4jCOxVbfDXSr+43xEFrlUfOwAAAAAAAAAAAAAAkN9/mtdZV+FuccEAAAAASUVORK5CYII='))
$form.Icon=[System.Drawing.Icon]::new($script:IconStream)
} catch {
    # Some .NET/Windows installations cannot decode PNG-compressed ICO streams.
    # The backup program is still usable with the default window icon.
    if ($script:IconStream) { $script:IconStream.Dispose() }
    $script:IconStream = $null
}

# Header logo: embedded UI glyph drawn locally, not an external resource.
$brand=New-Object System.Windows.Forms.Panel
$brand.Size=[System.Drawing.Size]::new(54,54);$brand.Location=[System.Drawing.Point]::new(30,21)
$brand.BackColor=UiColor '#E3EEFF'
$brand.add_Paint({
    param($sender,$e)
    $g=$e.Graphics
    $g.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $b=[System.Drawing.SolidBrush]::new((UiColor '#5379B9'))
    $g.FillRectangle($b,11,19,32,24)
    $g.FillRectangle($b,14,15,15,7)
    $b.Dispose()
    $p=[System.Drawing.Pen]::new([System.Drawing.Color]::White,2.8)
    $g.DrawLine($p,27,22,27,35);$g.DrawLine($p,21,29,27,35);$g.DrawLine($p,33,29,27,35)
    $p.Dispose()
})
$form.Controls.Add($brand)
$title=Label 'usersbackup' 96 14 440 49 20 '#273951';$title.Font=UiFont 20 ([System.Drawing.FontStyle]::Bold)
$form.Controls.Add($title)
$subtitle=Label 'Windows kullanıcı yedekleme ve geri yükleme' 98 63 710 25 9.5 '#8391A2'
$form.Controls.Add($subtitle)
$accountLabel=Label ('Oturum: '+$script:Identity.Account) 650 29 290 26 9.1 '#6C7D92'
$accountLabel.TextAlign='MiddleRight'
$form.Controls.Add($accountLabel)

$tabs=New-Object System.Windows.Forms.TabControl
$tabs.Location=[System.Drawing.Point]::new(28,96);$tabs.Size=[System.Drawing.Size]::new(924,562)
$tabs.Font=UiFont 10
$pageBackup=New-Object System.Windows.Forms.TabPage
$pageBackup.Text='  Yedekleme  ';$pageBackup.BackColor=UiColor '#F3F6FA'
$pageBackup.AutoScroll=$true;$pageBackup.AutoScrollMinSize=[System.Drawing.Size]::new(0,548)
$pageRestore=New-Object System.Windows.Forms.TabPage
$pageRestore.Text='  Geri Yükleme  ';$pageRestore.BackColor=UiColor '#F3F6FA'
$pageRestore.AutoScroll=$true;$pageRestore.AutoScrollMinSize=[System.Drawing.Size]::new(0,548)
[void]$tabs.TabPages.Add($pageBackup);[void]$tabs.TabPages.Add($pageRestore)
$form.Controls.Add($tabs)

# Backup tab - target disks
$diskCard=Card 13 14 889 116
$pageBackup.Controls.Add($diskCard)
$diskCard.Controls.Add((Label 'HEDEF DİSK' 17 12 240 25 10 '#314B6C'))
$diskCard.Controls.Add((Label 'EXE hangi diskteyse varsayılan odur; istersen değiştir.' 17 35 820 19 8.7 '#8190A3'))
$diskBox=New-Object System.Windows.Forms.ComboBox
$diskBox.Location=[System.Drawing.Point]::new(17,60);$diskBox.Size=[System.Drawing.Size]::new(690,29)
$diskBox.DropDownStyle='DropDownList';$diskBox.DisplayMember='Display'
$diskCard.Controls.Add($diskBox)
$diskRefresh=Button 'Yenile' 720 59 145 30
$diskCard.Controls.Add($diskRefresh)
$pathPreview=Label '' 18 93 849 19 8.7 '#7489A6'
$diskCard.Controls.Add($pathPreview)

$filesCard=Card 13 140 889 235
$pageBackup.Controls.Add($filesCard)
$filesCard.Controls.Add((Label 'KULLANICI KLASÖRLERİ' 17 12 480 24 10 '#314B6C'))
$filesCard.Controls.Add((Label 'Standart klasörleri işaretle veya herhangi bir erişilebilir klasör ekle.' 17 34 840 21 8.7 '#8190A3'))
$folderList=New-Object System.Windows.Forms.CheckedListBox
$folderList.Location=[System.Drawing.Point]::new(17,59);$folderList.Size=[System.Drawing.Size]::new(848,120)
$folderList.CheckOnClick=$true;$folderList.DisplayMember='Display';$folderList.HorizontalScrollbar=$true
$folderList.IntegralHeight=$false;$folderList.BackColor=UiColor '#FCFDFF'
$filesCard.Controls.Add($folderList)
$addFolder=Button '+ Klasör ekle' 17 190 156 31 '#E7EFFF' '#4169A9'
$removeFolder=Button 'Özeli kaldır' 184 190 150 31
$filesCard.Controls.Add($addFolder);$filesCard.Controls.Add($removeFolder)
$folderCount=Label 'Seçili: 0' 676 194 190 24 9 '#79899C'
$folderCount.TextAlign='MiddleRight';$filesCard.Controls.Add($folderCount)

$specialCard=Card 13 385 889 147
$pageBackup.Controls.Add($specialCard)
$specialCard.Controls.Add((Label 'DİĞER YEDEKLER' 17 12 480 24 10 '#314B6C'))
$specialCard.Controls.Add((Label 'Tarayıcı şifreleri ve oturum bilgileri alınmaz. INF sürücü aktarımı ayrı UAC isteyebilir.' 17 34 843 21 8.7 '#8190A3'))
$cbBrowser=New-Object System.Windows.Forms.CheckBox
$cbBrowser.Text='Chrome / Edge / Firefox favorileri';$cbBrowser.Checked=$true
$cbBrowser.Location=[System.Drawing.Point]::new(19,64);$cbBrowser.Size=[System.Drawing.Size]::new(420,27)
$specialCard.Controls.Add($cbBrowser)
$cbOutlook=New-Object System.Windows.Forms.CheckBox
$cbOutlook.Text='Outlook PST dosyaları';$cbOutlook.Location=[System.Drawing.Point]::new(460,64)
$cbOutlook.Size=[System.Drawing.Size]::new(388,27);$specialCard.Controls.Add($cbOutlook)
$cbPrograms=New-Object System.Windows.Forms.CheckBox
$cbPrograms.Text='Kurulu program listesi';$cbPrograms.Checked=$true
$cbPrograms.Location=[System.Drawing.Point]::new(19,101)
$cbPrograms.Size=[System.Drawing.Size]::new(420,27);$specialCard.Controls.Add($cbPrograms)
$cbDrivers=New-Object System.Windows.Forms.CheckBox
$cbDrivers.Text='INF sürücü paketleri (yetki ister)';$cbDrivers.Location=[System.Drawing.Point]::new(460,101)
$cbDrivers.Size=[System.Drawing.Size]::new(393,27);$specialCard.Controls.Add($cbDrivers)

# Restore tab
$restoreSourceCard=Card 13 14 889 132
$pageRestore.Controls.Add($restoreSourceCard)
$restoreSourceCard.Controls.Add((Label 'YEDEK KAYNAĞI' 17 12 700 25 10 '#314B6C'))
$restoreSourceCard.Controls.Add((Label 'SSD içinden örneğin D:\BACKUP\ahmet klasörünü seç.' 17 34 810 21 8.8 '#8190A3'))
$restorePath=New-Object System.Windows.Forms.TextBox
$restorePath.ReadOnly=$true;$restorePath.Location=[System.Drawing.Point]::new(17,61)
$restorePath.Size=[System.Drawing.Size]::new(673,28);$restorePath.BackColor=UiColor '#FBFCFF'
$restoreSourceCard.Controls.Add($restorePath)
$chooseRestore=Button 'Yedek seç' 705 60 160 30
$restoreSourceCard.Controls.Add($chooseRestore)
$restoreInfo=Label 'Henüz bir yedek seçilmedi.' 18 99 845 21 8.8 '#6D7D90'
$restoreSourceCard.Controls.Add($restoreInfo)

$restoreCard=Card 13 156 889 213
$pageRestore.Controls.Add($restoreCard)
$restoreCard.Controls.Add((Label 'GERİ YÜKLENECEK VERİLER' 17 12 690 24 10 '#314B6C'))
$restoreCard.Controls.Add((Label 'Yalnızca mevcut oturumdaki kullanıcıya geri yüklenir.' 17 35 800 20 8.8 '#8190A3'))
$restoreList=New-Object System.Windows.Forms.CheckedListBox
$restoreList.Location=[System.Drawing.Point]::new(17,61);$restoreList.Size=[System.Drawing.Size]::new(848,135)
$restoreList.CheckOnClick=$true;$restoreList.DisplayMember='Display'
$restoreList.IntegralHeight=$false;$restoreList.BackColor=UiColor '#FCFDFF'
$restoreCard.Controls.Add($restoreList)

$restoreOptions=Card 13 380 889 152
$pageRestore.Controls.Add($restoreOptions)
$restoreOptions.Controls.Add((Label 'GERİ YÜKLEME KURALLARI' 17 12 800 25 10 '#314B6C'))
$restoreOptions.Controls.Add((Label 'Dosya çakışmalarında:' 18 51 165 23 9 '#53647B'))
$conflictBox=New-Object System.Windows.Forms.ComboBox
$conflictBox.DropDownStyle='DropDownList';$conflictBox.Location=[System.Drawing.Point]::new(195,48)
$conflictBox.Size=[System.Drawing.Size]::new(520,27);$conflictBox.BackColor=UiColor '#FFFFFF';$conflictBox.ForeColor=UiColor '#39465A'
[void]$conflictBox.Items.Add('Mevcut dosyayı atla (önerilen)')
[void]$conflictBox.Items.Add('Yeni dosyayı farklı isimle kaydet')
[void]$conflictBox.Items.Add('Mevcut dosyanın üzerine yaz (onay gerekir)')
$conflictBox.SelectedIndex=0;$restoreOptions.Controls.Add($conflictBox)
$directBrowser=New-Object System.Windows.Forms.CheckBox
$directBrowser.Text='Chrome / Edge favorilerini mevcut profillere uygula (mevcutlar önceden korunur)'
$directBrowser.Location=[System.Drawing.Point]::new(18,88);$directBrowser.Size=[System.Drawing.Size]::new(835,25)
$restoreOptions.Controls.Add($directBrowser)
$restoreOptions.Controls.Add((Label 'Firefox favorileri içe aktarma dosyası olarak hazırlanır; sürücüler otomatik kurulmaz.' 18 120 835 19 8.3 '#8090A2'))

# Progress, common footer
$progressCard=Card 28 671 924 64
$form.Controls.Add($progressCard)
$status=Label 'Hazır. Yedekleme veya geri yükleme sekmesini kullan.' 14 5 730 22 9.1 '#607389'
$progressCard.Controls.Add($status)
$progress=New-Object System.Windows.Forms.ProgressBar
$progress.Location=[System.Drawing.Point]::new(14,33);$progress.Size=[System.Drawing.Size]::new(814,17)
$progress.Minimum=0;$progress.Maximum=100;$progress.Value=0;$progress.Style='Continuous'
$progressCard.Controls.Add($progress)
$percentage=Label '0%' 841 27 61 24 11 '#5175B7';$percentage.TextAlign='MiddleRight'
$percentage.Font=UiFont 11 ([System.Drawing.FontStyle]::Bold)
$progressCard.Controls.Add($percentage)
$start=Button 'Yedeklemeyi Başlat' 28 747 212 36 '#5278BD' '#FFFFFF'
$start.Font=UiFont 10 ([System.Drawing.FontStyle]::Bold)
$close=Button 'Kapat' 253 747 135 36 '#E5EAF2' '#52657D'
$report=Button 'Son TXT Raporu' 402 747 179 36 '#E5EAF2' '#52657D';$report.Enabled=$false
$form.Controls.Add($start);$form.Controls.Add($close);$form.Controls.Add($report)
$footerNote=Label 'Kaynak dosyalar silinmez  |  Yönetici izni açılışta istenmez' 592 755 361 22 8.3 '#7D8A9D'
$footerNote.Anchor='Bottom,Right';$footerNote.TextAlign='MiddleRight'
$form.Controls.Add($footerNote)


# Responsive layout: window is resizable; sections follow the right edge,
# footer follows the bottom, and tabs scroll on shorter screens.
$tabs.Anchor = 'Top,Bottom,Left,Right'
$progressCard.Anchor = 'Bottom,Left,Right'
$start.Anchor = 'Bottom,Left'
$close.Anchor = 'Bottom,Left'
$report.Anchor = 'Bottom,Left'
$accountLabel.Anchor = 'Top,Right'
foreach ($section in @($diskCard,$filesCard,$specialCard,$restoreSourceCard,$restoreCard,$restoreOptions)) {
    $section.Anchor = 'Top,Left,Right'
}
foreach ($field in @($folderList,$restoreList,$pathPreview,$restoreInfo)) {
    $field.Anchor = 'Top,Left,Right'
}
$diskBox.Anchor = 'Top,Left,Right'
$diskRefresh.Anchor = 'Top,Right'
$restorePath.Anchor = 'Top,Left,Right'
$chooseRestore.Anchor = 'Top,Right'
$folderCount.Anchor = 'Top,Right'
$conflictBox.Anchor = 'Top,Left,Right'
$directBrowser.Anchor = 'Top,Left,Right'
$progress.Anchor = 'Top,Left,Right'
$percentage.Anchor = 'Top,Right'

# These controls have widths based on two columns, not on fixed pixel positions.
# Keep everything readable when the window is narrowed or widened.
$adjustPageLayout = {
    $backupWidth = $diskCard.ClientSize.Width
    if($backupWidth -gt 0) {
        $diskBox.Width=[Math]::Max(240,$backupWidth-17-14-145-13)
        $diskRefresh.Left=$backupWidth-17-145
        $pathPreview.Width=[Math]::Max(100,$backupWidth-35)
        $folderList.Width=[Math]::Max(200,$filesCard.ClientSize.Width-36)
        $folderCount.Left=$filesCard.ClientSize.Width-17-$folderCount.Width
        $specialWidth=$specialCard.ClientSize.Width
        $colStart=[int][Math]::Floor($specialWidth/2)
        $cbBrowser.Width=[Math]::Max(190,$colStart-35)
        $cbPrograms.Width=$cbBrowser.Width
        $cbOutlook.Left=$colStart
        $cbDrivers.Left=$colStart
        $cbOutlook.Width=[Math]::Max(180,$specialWidth-$colStart-15)
        $cbDrivers.Width=$cbOutlook.Width
    }
    $restoreWidth=$restoreSourceCard.ClientSize.Width
    if($restoreWidth -gt 0) {
        $restorePath.Width=[Math]::Max(220,$restoreWidth-17-14-160-15)
        $chooseRestore.Left=$restoreWidth-17-160
        $restoreInfo.Width=[Math]::Max(100,$restoreWidth-35)
        $restoreList.Width=[Math]::Max(200,$restoreCard.ClientSize.Width-36)
        $conflictBox.Width=[Math]::Max(160,$restoreOptions.ClientSize.Width-195-18)
        $directBrowser.Width=[Math]::Max(220,$restoreOptions.ClientSize.Width-36)
    }
    $progress.Width=[Math]::Max(100,$progressCard.ClientSize.Width-14-96)
    $percentage.Left=$progressCard.ClientSize.Width-75
    $status.Width=[Math]::Max(160,$progressCard.ClientSize.Width-30)
}
$diskCard.add_Resize($adjustPageLayout)
$filesCard.add_Resize($adjustPageLayout)
$specialCard.add_Resize($adjustPageLayout)
$restoreSourceCard.add_Resize($adjustPageLayout)
$restoreCard.add_Resize($adjustPageLayout)
$restoreOptions.add_Resize($adjustPageLayout)
$progressCard.add_Resize($adjustPageLayout)
$form.add_Resize({ $footerNote.Visible=($form.ClientSize.Width -ge 960) })
& $adjustPageLayout

function Update-FolderCount { $folderCount.Text=('Seçili: {0} klasör' -f $folderList.CheckedItems.Count) }
function Update-PathPreview {
    if($diskBox.SelectedItem){
        $root=[string]$diskBox.SelectedItem.Root
        $pathPreview.Text='Hedef: '+[System.IO.Path]::Combine($root,'BACKUP',$script:Identity.Username)
    } else { $pathPreview.Text='Disk bulunamadı.' }
}
function Reload-Disks {
    $preferred=$script:ProgramRoot
    if($diskBox.SelectedItem){$preferred=[string]$diskBox.SelectedItem.Root}
    $diskBox.Items.Clear();$sel=-1;$i=0
    foreach($d in [System.IO.DriveInfo]::GetDrives()){
        try{
            if(-not $d.IsReady -or $d.DriveType -notin @([System.IO.DriveType]::Fixed,[System.IO.DriveType]::Removable)){continue}
            $label=$d.VolumeLabel;if(-not $label){$label='Disk'}
            $entry=[pscustomobject]@{Root=$d.Name;Display=('{0} ({1}) - Bos alan {2}' -f $label,$d.Name.TrimEnd('\'),(DisplaySize $d.AvailableFreeSpace))}
            [void]$diskBox.Items.Add($entry)
            if($preferred -eq $d.Name){$sel=$i};$i++
        }catch{}
    }
    if($diskBox.Items.Count -gt 0){if($sel -lt 0){$sel=0};$diskBox.SelectedIndex=$sel}
    Update-PathPreview
}

foreach($def in @(
    @{Key='Desktop';Label='Masaüstü';Default=$true},
    @{Key='Downloads';Label='İndirilenler';Default=$true},
    @{Key='Documents';Label='Belgeler';Default=$false},
    @{Key='Pictures';Label='Resimler';Default=$false},
    @{Key='Videos';Label='Videolar';Default=$false},
    @{Key='Music';Label='Müzik';Default=$false}
)){
    $p=[string]$script:Known[$def.Key]
    if(-not $p){continue}
    $exists=[System.IO.Directory]::Exists($p)
    $item=[pscustomobject]@{Kind='Known';Name=$def.Key;Source=$p;Display=($def.Label+'  |  '+$p+$(if(-not $exists){'  (bulunamadı)'}else{''}))}
    [void]$folderList.Items.Add($item,($def.Default -and $exists))
}
Update-FolderCount
Reload-Disks
$diskBox.add_SelectedIndexChanged({Update-PathPreview})
$diskRefresh.add_Click({Reload-Disks})
$folderList.add_ItemCheck({
    $n=$folderList.CheckedItems.Count
    if($_.NewValue -eq 'Checked' -and $_.CurrentValue -ne 'Checked'){$n++}
    if($_.NewValue -eq 'Unchecked' -and $_.CurrentValue -eq 'Checked'){$n--}
    $folderCount.Text='Seçili: '+$n+' klasör'
})
$addFolder.add_Click({
    $pick=New-Object System.Windows.Forms.FolderBrowserDialog
    $pick.Description='Yedeklenecek özel klasörü seç'
    if($pick.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK){return}
    $p=$pick.SelectedPath
    foreach($item in $folderList.Items){
        if($item.Source.TrimEnd('\').Equals($p.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)){
            $folderList.SetItemChecked($folderList.Items.IndexOf($item),$true);return
        }
    }
    $name=[System.IO.Path]::GetFileName($p.TrimEnd('\'))
    if(-not $name){$name='OzelKlasor'}
    $item=[pscustomobject]@{Kind='Custom';Name=$name;Source=$p;Display=('Özel: '+$name+'  |  '+$p)}
    [void]$folderList.Items.Add($item,$true);Update-FolderCount
})
$removeFolder.add_Click({
    $i=$folderList.SelectedIndex;if($i -lt 0){return}
    if($folderList.Items[$i].Kind -ne 'Custom'){Message 'Standart klasörleri kaldırmak yerine işaretlerini kapatabilirsin.';return}
    $folderList.Items.RemoveAt($i);Update-FolderCount
})

# Background work: the runspace never reads or writes WinForms controls.
$engine=@'
param($cfg,$events,$cancel)
$ErrorActionPreference='Stop'
$startTime=Get-Date
$script:warn=New-Object 'System.Collections.Generic.List[string]'
$script:copied=0L;$script:skipped=0L;$script:failed=0L
$script:total=0L;$script:done=0L;$script:files=0L
$script:tasks=New-Object 'System.Collections.Generic.List[object]'
$script:dirs=New-Object 'System.Collections.Generic.List[string]'
$script:entries=New-Object 'System.Collections.Generic.List[object]'
$script:state='Tamamlandı'
$script:driverResult='Seçilmedi'
$script:reportPath=$null
$script:lastNotify=[System.Diagnostics.Stopwatch]::StartNew()
$script:manifestPath=$null

function Event([string]$kind,[string]$text,[long]$bytes=0,[long]$size=0){
    $events.Enqueue([pscustomobject]@{Kind=$kind;Text=$text;Done=$bytes;Total=$size})
}
function CheckStop {if($cancel.IsCancellationRequested){throw [OperationCanceledException]::new('İşlem durduruldu.')}}
function Warn([string]$m){$script:warn.Add($m);$script:failed++}
function IsInside([string]$child,[string]$parent){
    $c=[System.IO.Path]::GetFullPath($child).TrimEnd('\');$p=[System.IO.Path]::GetFullPath($parent).TrimEnd('\')
    $c.Equals($p,[StringComparison]::OrdinalIgnoreCase) -or $c.StartsWith($p+'\',[StringComparison]::OrdinalIgnoreCase)
}
function Safe([string]$n){
    $x=[regex]::Replace($n,'[\\/:*?"<>|\x00-\x1f]','_').Trim().TrimEnd('.')
    if(-not $x){return 'Klasor'}
    if($x -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$'){return '_'+$x}
    return $x
}
function AddFile([string]$source,[string]$dest,[bool]$overwriteExisting=$false){
    CheckStop
    try{
        $fi=[System.IO.FileInfo]::new($source)
        if(-not $fi.Exists){Warn ('Eksik dosya: '+$source);return}
        if(($fi.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){Warn ('Bağlantı/bulut dosyası atlandı: '+$source);return}
        $script:files++
        if([System.IO.File]::Exists($dest)){
            $d=[System.IO.FileInfo]::new($dest)
            $diff=[Math]::Abs(($d.LastWriteTimeUtc-$fi.LastWriteTimeUtc).TotalSeconds)
            if(($cfg.Mode -eq 'Backup' -and $d.Length -eq $fi.Length -and $diff -le 2) -or
               ($cfg.Mode -eq 'Restore' -and $cfg.Conflict -eq 'Skip') -or
               ($cfg.Mode -eq 'Restore' -and $d.Length -eq $fi.Length -and $diff -le 2)){
                $script:skipped++;return
            }
            if($cfg.Mode -eq 'Restore' -and $cfg.Conflict -eq 'Rename'){
                $dir=[System.IO.Path]::GetDirectoryName($dest);$stem=[System.IO.Path]::GetFileNameWithoutExtension($dest)
                $ext=[System.IO.Path]::GetExtension($dest);$num=1
                do {$dest=[System.IO.Path]::Combine($dir,('{0}_usersbackup_{1}{2}' -f $stem,$num,$ext));$num++}
                while([System.IO.File]::Exists($dest))
            }
        }
        $script:tasks.Add([pscustomobject]@{Source=$source;Dest=$dest;Size=[long]$fi.Length;Time=$fi.LastWriteTimeUtc})
        $script:total += [long]$fi.Length
    }catch{Warn ('Dosya okunamadı: '+$source+' | '+$_.Exception.Message)}
}
function AddTree([string]$from,[string]$to){
    if(-not [System.IO.Directory]::Exists($from)){Warn ('Klasör yok: '+$from);return}
    $root=[System.IO.Path]::GetFullPath($from).TrimEnd('\')
    $stack=New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($root)
    while($stack.Count -gt 0){
        CheckStop
        $d=$stack.Pop()
        try{
            $attrs=[System.IO.File]::GetAttributes($d)
            if(($attrs -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){Warn ('Bağlantılı klasör atlandı: '+$d);continue}
            $rel=$d.Substring($root.Length).TrimStart('\')
            if($rel){$script:dirs.Add([System.IO.Path]::Combine($to,$rel))}else{$script:dirs.Add($to)}
            $subs=[System.IO.Directory]::GetDirectories($d)
            $fs=[System.IO.Directory]::GetFiles($d)
        }catch{Warn ('Klasör listelenemedi: '+$d+' | '+$_.Exception.Message);continue}
        foreach($sub in $subs){
            try{if(([System.IO.File]::GetAttributes($sub) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){
                Warn ('Bağlantılı klasör atlandı: '+$sub)
            }else{$stack.Push($sub)}}catch{Warn ('Alt klasör: '+$sub+' | '+$_.Exception.Message)}
        }
        foreach($f in $fs){
            $relFile=$f.Substring($root.Length).TrimStart('\')
            AddFile $f ([System.IO.Path]::Combine($to,$relFile))
            if(($script:files % 500) -eq 0 -and $script:files -gt 0){Event 'Scan' ('Taranan dosya: '+$script:files)}
        }
    }
}
function HashFile([string]$path){
    $algo=[System.Security.Cryptography.SHA256]::Create();$stream=$null
    try{
        $stream=[System.IO.FileStream]::new($path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::Read)
        return [Convert]::ToBase64String($algo.ComputeHash($stream))
    }finally{if($stream){$stream.Dispose()};$algo.Dispose()}
}
function TransferFiles {
    $root=[System.IO.Path]::GetPathRoot([string]$cfg.WorkingTarget)
    try {
        $disk=[System.IO.DriveInfo]::new($root)
        if($script:total -gt 0 -and $disk.AvailableFreeSpace -lt ($script:total + 64MB)){
            throw ('Yetersiz disk alanı: '+$disk.AvailableFreeSpace+' bayt boş, '+$script:total+' bayt gerekli.')
        }
    } catch [System.IO.IOException] { Warn ('Boş alan doğrulaması yapılamadı: '+$_.Exception.Message) }
      catch [System.ArgumentException] { Warn ('Bu hedefin boş alan bilgisi okunamadı: '+$_.Exception.Message) }
    foreach($dir in $script:dirs){CheckStop;try{[void][System.IO.Directory]::CreateDirectory($dir)}catch{Warn ('Dizin oluşturma: '+$dir+' | '+$_.Exception.Message)}}
    $buf=New-Object byte[] (1024*1024)
    foreach($task in $script:tasks){
        CheckStop
        $source=$null;$dest=$null;$partial=$null;$previous=$null
        try{
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($task.Dest))
            $partial=$task.Dest+'.usersbackup-part-'+[guid]::NewGuid().ToString('N')
            $source=[System.IO.FileStream]::new($task.Source,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::Read)
            $dest=[System.IO.FileStream]::new($partial,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None)
            while($true){
                CheckStop
                $n=$source.Read($buf,0,$buf.Length)
                if($n -le 0){break}
                $dest.Write($buf,0,$n)
                $script:done += $n
                if($script:lastNotify.ElapsedMilliseconds -ge 170){
                    Event 'Progress' ('Kopyalanıyor: '+[System.IO.Path]::GetFileName($task.Source)) $script:done $script:total
                    $script:lastNotify.Restart()
                }
            }
            $dest.Flush();$source.Dispose();$source=$null;$dest.Dispose();$dest=$null
            CheckStop
            $srcNow=[System.IO.FileInfo]::new($task.Source)
            if($srcNow.Length -ne $task.Size -or $srcNow.LastWriteTimeUtc -ne $task.Time){throw 'Kaynak kopyalama sırasında değişti.'}
            if((HashFile $task.Source) -ne (HashFile $partial)){throw 'SHA-256 doğrulaması başarısız.'}
            [System.IO.File]::SetLastWriteTimeUtc($partial,$task.Time)
            if([System.IO.File]::Exists($task.Dest)){
                $previous=$task.Dest+'.usersbackup-prev-'+[guid]::NewGuid().ToString('N')
                [System.IO.File]::Move($task.Dest,$previous)
            }
            try{[System.IO.File]::Move($partial,$task.Dest);$partial=$null}
            catch{
                if($previous -and [System.IO.File]::Exists($previous)){
                    try{[System.IO.File]::Move($previous,$task.Dest);$previous=$null}catch{}
                }
                throw
            }
            if($previous -and [System.IO.File]::Exists($previous)){
                try{[System.IO.File]::Delete($previous)}catch{Warn ('Eski kopya temizlenemedi: '+$previous)}
                $previous=$null
            }
            $script:copied++
        }catch [OperationCanceledException] {throw}
        catch{Warn ('Kopyalanamadı: '+$task.Source+' | '+$_.Exception.Message)}
        finally{
            if($source){$source.Dispose()};if($dest){$dest.Dispose()}
            if($partial -and [System.IO.File]::Exists($partial)){try{[System.IO.File]::Delete($partial)}catch{}}
        }
        Event 'Progress' ('{0} kopya / {1} atlanan / {2} hata' -f $script:copied,$script:skipped,$script:failed) $script:done $script:total
    }
}
function Chromium([string]$label,[string]$userData,[string]$base){
    if(-not [System.IO.Directory]::Exists($userData)){return}
    foreach($dir in [System.IO.Directory]::GetDirectories($userData)){
        CheckStop;$browserProfileName=[System.IO.Path]::GetFileName($dir)
        if($browserProfileName -ne 'Default' -and $browserProfileName -notmatch '^Profile \d+$'){continue}
        $book=[System.IO.Path]::Combine($dir,'Bookmarks')
        if([System.IO.File]::Exists($book)){AddFile $book ([System.IO.Path]::Combine($base,'BrowserBookmarks',$label,$browserProfileName,'Bookmarks'))}
    }
}
function AddBrowsers {
    Event 'Scan' 'Tarayıcı favorileri taranıyor...'
    Chromium 'Chrome' ([System.IO.Path]::Combine($cfg.LocalAppData,'Google','Chrome','User Data')) $cfg.WorkingTarget
    Chromium 'Edge' ([System.IO.Path]::Combine($cfg.LocalAppData,'Microsoft','Edge','User Data')) $cfg.WorkingTarget
    $fx=[System.IO.Path]::Combine($cfg.RoamingAppData,'Mozilla','Firefox','Profiles')
    if([System.IO.Directory]::Exists($fx)){
        foreach($dir in [System.IO.Directory]::GetDirectories($fx)){
            CheckStop;$browserProfileName=[System.IO.Path]::GetFileName($dir)
            $backups=[System.IO.Path]::Combine($dir,'bookmarkbackups')
            if(-not [System.IO.Directory]::Exists($backups)){Warn ('Firefox yer imi yedeği bulunmadı: '+$browserProfileName);continue}
            foreach($file in [System.IO.Directory]::GetFiles($backups,'*.jsonlz4')){
                AddFile $file ([System.IO.Path]::Combine($cfg.WorkingTarget,'BrowserBookmarks','Firefox',$browserProfileName,[System.IO.Path]::GetFileName($file)))
            }
        }
    }
}
function AddOutlook {
    Event 'Scan' 'Outlook PST dosyaları aranıyor...'
    $roots=@([System.IO.Path]::Combine($cfg.Documents,'Outlook Files'),[System.IO.Path]::Combine($cfg.LocalAppData,'Microsoft','Outlook'))
    $seen=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $idx=0
    foreach($root in $roots){
        if(-not [System.IO.Directory]::Exists($root)){continue}
        $stk=New-Object 'System.Collections.Generic.Stack[string]';$stk.Push($root)
        while($stk.Count -gt 0){
            CheckStop;$d=$stk.Pop()
            try{
                if(([System.IO.File]::GetAttributes($d) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){continue}
                $children=[System.IO.Directory]::GetDirectories($d)
                foreach($c in $children){$stk.Push($c)}
                foreach($pst in [System.IO.Directory]::GetFiles($d,'*.pst')){
                    if($seen.Add($pst)){
                        $relative=$pst.Substring($root.TrimEnd('\').Length).TrimStart('\')
                        AddFile $pst ([System.IO.Path]::Combine($cfg.WorkingTarget,'Outlook',('Source'+$idx),$relative))
                    }
                }
            }catch{Warn ('PST arama: '+$d+' | '+$_.Exception.Message)}
        }
        $idx++
    }
}
function Inventory {
    CheckStop
    $programs=New-Object 'System.Collections.Generic.List[object]'
    foreach($path in @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')){
        try{
            foreach($p in @(Get-ItemProperty -Path $path -ErrorAction SilentlyContinue)){
                if($p.DisplayName){$programs.Add([pscustomobject]@{Name=[string]$p.DisplayName;Version=[string]$p.DisplayVersion;Publisher=[string]$p.Publisher})}
            }
        }catch{Warn ('Program envanteri okunamadı: '+$_.Exception.Message)}
    }
    $out=[System.IO.Path]::Combine($cfg.WorkingTarget,'ProgramInventory')
    [void][System.IO.Directory]::CreateDirectory($out)
    $csv=[System.IO.Path]::Combine($out,'InstalledPrograms.csv')
    @($programs.ToArray() | Sort-Object Name -Unique) | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
    $txt=[System.IO.Path]::Combine($out,'README.txt')
    [System.IO.File]::WriteAllText($txt,'Bu dosya program listesidir; programları otomatik kurmaz.',[System.Text.UTF8Encoding]::new($true))
    Event 'Scan' ('Program envanteri hazır: '+$programs.Count)
}
function ExportDrivers {
    CheckStop
    $dest=[System.IO.Path]::Combine($cfg.WorkingTarget,'Drivers')
    [void][System.IO.Directory]::CreateDirectory($dest)
    Event 'Driver' 'INF sürücü paketleri dışa aktarılıyor. Windows UAC penceresi açılabilir.'
    try{
        $exe=[System.IO.Path]::Combine($env:WINDIR,'System32','pnputil.exe')
        # Launch the OS-supported driver tool in its own elevated process only for this opt-in feature.
        $quoted=' /export-driver * "'+$dest+'"'
        $p=Start-Process -FilePath $exe -ArgumentList $quoted -Verb RunAs -PassThru -Wait
        if($p.ExitCode -eq 0){$script:driverResult='Başarılı';Event 'Driver' 'INF paketleri alındı.'}
        else{$script:driverResult='Başarısız';Warn ('PnPUtil çıkış kodu: '+$p.ExitCode)}
    }catch{$script:driverResult='Başarısız/izin verilmedi';Warn ('Sürücü yedekleme: '+$_.Exception.Message)}
}
function RestoreBrowserFiles([string]$sourceRoot){
    $in=[System.IO.Path]::Combine($sourceRoot,'BrowserBookmarks')
    if(-not [System.IO.Directory]::Exists($in)){return}
    # Always stage an importable copy under Documents. Browser-profile replacement is explicit opt-in.
    AddTree $in ([System.IO.Path]::Combine($cfg.Documents,'usersbackup_BrowserImport'))
    if(-not $cfg.DirectBrowser){return}
    foreach($browser in @('Chrome','Edge')){
        CheckStop
        $process=if($browser -eq 'Chrome'){'chrome'}else{'msedge'}
        if(@(Get-Process -Name $process -ErrorAction SilentlyContinue).Count -gt 0){Warn ($browser+' açık: profil dosyası değiştirilmedi. İçe aktarma kopyası hazırlandı.');continue}
        $base=if($browser -eq 'Chrome'){
            [System.IO.Path]::Combine($cfg.LocalAppData,'Google','Chrome','User Data')
        }else{[System.IO.Path]::Combine($cfg.LocalAppData,'Microsoft','Edge','User Data')}
        $source=[System.IO.Path]::Combine($in,$browser)
        if(-not [System.IO.Directory]::Exists($source)){continue}
        foreach($profileDir in [System.IO.Directory]::GetDirectories($source)){
            $browserProfileName=[System.IO.Path]::GetFileName($profileDir)
            if($browserProfileName -ne 'Default' -and $browserProfileName -notmatch '^Profile \d+$'){continue}
            $targetDir=[System.IO.Path]::Combine($base,$browserProfileName)
            if(-not [System.IO.Directory]::Exists($targetDir)){Warn ($browser+' profili mevcut değil: '+$browserProfileName+'. İçe aktarma kopyası hazırlandı.');continue}
            $src=[System.IO.Path]::Combine($profileDir,'Bookmarks')
            if(-not [System.IO.File]::Exists($src)){continue}
            $dst=[System.IO.Path]::Combine($targetDir,'Bookmarks')
            if([System.IO.File]::Exists($dst)){
                # Preserve exact pre-restore bookmarks in adjacent timestamped file.
                $prior=$dst+'.before-usersbackup-'+(Get-Date -Format 'yyyyMMdd_HHmmss')
                try{[System.IO.File]::Copy($dst,$prior,$false)}catch{Warn ('Önceki favoriler korunamadı, profil değiştirilmedi: '+$dst);continue}
            }
            # Explicit checkbox is treated as consent to update target bookmarks.
            # Use Overwrite policy only for this special, protected operation.
            $oldConflict=$cfg.Conflict;$cfg.Conflict='Overwrite'
            try{AddFile $src $dst}finally{$cfg.Conflict=$oldConflict}
        }
    }
}
function Backup {
    $root=[string]$cfg.WorkingTarget
    [void][System.IO.Directory]::CreateDirectory($root)
    $script:manifestPath=[System.IO.Path]::Combine($root,'backup_manifest.json')
    if([System.IO.File]::Exists($script:manifestPath)){
        try{
            $prior=Get-Content -LiteralPath $script:manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if(-not $prior.UserSid -or $prior.UserSid -ne $cfg.Sid -or $prior.Account -ne $cfg.Account){
                throw 'Farklı domain veya SID kullanıcısına ait mevcut yedek. İşlem güvenlik için durduruldu.'
            }
        }catch{
            if($_.Exception.Message -like 'Farklı domain*'){throw}
            throw ('Mevcut manifest okunamıyor; başka hesabın verisine yazmayı önlemek için işlem durduruldu: '+$_.Exception.Message)
        }
    }else{
        $existing=@([System.IO.Directory]::GetFileSystemEntries($root))
        if($existing.Count -gt 0){throw 'Manifesti olmayan dolu kullanıcı yedek klasörüne yazılmıyor. Önce bu klasörü kontrol et.'}
        # Without an initial manifest, an interrupted first backup cannot be resumed.
        # Mark the user-owned directory before any file transfers begin.
        $initial = [ordered]@{
            FormatVersion=3; Application='usersbackup'; Account=$cfg.Account
            Username=$cfg.Username; UserSid=$cfg.Sid
            CreatedAt=(Get-Date).ToString('o'); Status='Eksik'
            Folders=@(); Browsers=[bool]$cfg.Browsers; Outlook=[bool]$cfg.Outlook
            Drivers=[bool]$cfg.Drivers; DriverResult='Başlamadı'; Programs=[bool]$cfg.Programs
        }
        $initialJson = $initial | ConvertTo-Json -Depth 6
        [System.IO.File]::WriteAllText($script:manifestPath,$initialJson,[System.Text.UTF8Encoding]::new($true))
    }
    Event 'Scan' 'Kullanıcı klasörleri taranıyor...'
    $used=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($folder in @($cfg.Folders)){
        CheckStop
        $relative=if($folder.Kind -eq 'Known'){$folder.Name}else{'CustomFolders\'+(Safe $folder.Name)}
        if($used.Contains($relative)){
            $i=2;do{$relative='CustomFolders\'+(Safe $folder.Name)+'_'+$i;$i++}while($used.Contains($relative))
        }
        [void]$used.Add($relative)
        $script:entries.Add([pscustomobject]@{Name=$folder.Name;Kind=$folder.Kind;Relative=$relative;Source=$folder.Source})
        AddTree ([string]$folder.Source) ([System.IO.Path]::Combine($root,$relative))
    }
    if($cfg.Browsers){AddBrowsers}
    if($cfg.Outlook){AddOutlook}
    Event 'Plan' ('{0} dosya, {1} kopyalanacak, {2} atlandı' -f $script:files,$script:tasks.Count,$script:skipped) 0 $script:total
    TransferFiles
    if($cfg.Programs){CheckStop;Event 'Scan' 'Program listesi hazırlanıyor...';Inventory}
    if($cfg.Drivers){ExportDrivers}
}
function Restore {
    $sourceRoot=[System.IO.Path]::GetFullPath([string]$cfg.SourceRoot).TrimEnd('\')
    if(-not [System.IO.File]::Exists([System.IO.Path]::Combine($sourceRoot,'backup_manifest.json'))){throw 'Kaynak manifest bulunamadı.'}
    Event 'Scan' 'Geri yüklenecek dosyalar inceleniyor...'
    foreach($item in @($cfg.RestoreItems)){
        CheckStop
        $src=[System.IO.Path]::Combine($sourceRoot,[string]$item)
        if(-not [System.IO.Directory]::Exists($src)){Warn ('Yedek içinde bulunamadı: '+$item);continue}
        if($item -eq 'CustomFolders'){
            AddTree $src ([System.IO.Path]::Combine($cfg.Documents,'usersbackup_Restored','CustomFolders'))
        }elseif($item -eq 'BrowserBookmarks'){
            RestoreBrowserFiles $sourceRoot
        }elseif($item -eq 'Outlook'){
            AddTree $src ([System.IO.Path]::Combine($cfg.Documents,'Outlook Files','usersbackup_Imported'))
        }elseif($item -eq 'Drivers'){
            AddTree $src ([System.IO.Path]::Combine($cfg.Documents,'usersbackup_RestoredDrivers'))
        }elseif($item -eq 'ProgramInventory'){
            AddTree $src ([System.IO.Path]::Combine($cfg.Documents,'usersbackup_ProgramInventory'))
        }elseif($cfg.Known.ContainsKey($item) -and $cfg.Known[$item]){
            $tgt=[string]$cfg.Known[$item]
            if(IsInside $src $tgt -or IsInside $tgt $src){Warn ('Kaynak/hedef çakışıyor: '+$item);continue}
            AddTree $src $tgt
        }
    }
    Event 'Plan' ('{0} dosya planlandı, {1} atlandı.' -f $script:tasks.Count,$script:skipped) 0 $script:total
    TransferFiles
}
try{
    if($cfg.Mode -eq 'Backup'){Backup}else{Restore}
}catch [OperationCanceledException]{
    $script:state='Durduruldu';Event 'State' 'İşlem durduruldu; tamamlanan dosyalar korundu.' $script:done $script:total
}catch{
    $script:state='Hata';Warn ('Genel hata: '+$_.Exception.Message)
    Event 'State' ('İşlem tamamlanamadı: '+$_.Exception.Message) $script:done $script:total
}finally{
    if($script:state -eq 'Tamamlandı' -and $script:failed -gt 0){$script:state='Uyarılarla tamamlandı'}
    if($cfg.Mode -eq 'Backup' -and $script:state -in @('Tamamlandı','Uyarılarla tamamlandı')){
        try{
            $manifest=[ordered]@{
                FormatVersion=3;Application='usersbackup';Account=$cfg.Account;Username=$cfg.Username;UserSid=$cfg.Sid
                CreatedAt=(Get-Date).ToString('o');Status=$script:state
                Folders=@($script:entries.ToArray());Browsers=[bool]$cfg.Browsers;Outlook=[bool]$cfg.Outlook
                Drivers=[bool]$cfg.Drivers;DriverResult=$script:driverResult;Programs=[bool]$cfg.Programs
            }
            $json=$manifest|ConvertTo-Json -Depth 6
            $tmp=$script:manifestPath+'.tmp-'+[guid]::NewGuid().ToString('N')
            [System.IO.File]::WriteAllText($tmp,$json,[System.Text.UTF8Encoding]::new($true))
            if([System.IO.File]::Exists($script:manifestPath)){
                $previous=$script:manifestPath+'.previous-'+[guid]::NewGuid().ToString('N')
                [System.IO.File]::Move($script:manifestPath,$previous)
                try { [System.IO.File]::Move($tmp,$script:manifestPath) }
                catch { [System.IO.File]::Move($previous,$script:manifestPath); throw }
                try { [System.IO.File]::Delete($previous) } catch { }
            }else{[System.IO.File]::Move($tmp,$script:manifestPath)}
        }catch{Warn ('Manifest güncellenemedi: '+$_.Exception.Message);$script:state='Hata'}
    }
    $end=Get-Date
    $txt=New-Object 'System.Collections.Generic.List[string]'
    $txt.Add('usersbackup v3.0.2 - '+$cfg.Mode+' - TXT RAPOR')
    $txt.Add(('Durum: '+$script:state));$txt.Add(('Başlangıç: '+$startTime.ToString('yyyy-MM-dd HH:mm:ss')))
    $txt.Add(('Bitiş: '+$end.ToString('yyyy-MM-dd HH:mm:ss')))
    $txt.Add(('Hesap: '+$cfg.Account));$txt.Add(('Dosya: '+$script:files))
    $txt.Add(('Kopyalanan: '+$script:copied));$txt.Add(('Atlanan: '+$script:skipped))
    $txt.Add(('Hata / uyarı: '+$script:failed));$txt.Add(('Aktarılan bayt: '+$script:done))
    $txt.Add(('INF durumu: '+$script:driverResult));$txt.Add('')
    foreach($line in $script:warn){$txt.Add('[Uyarı] '+$line)}
    try{
        $reportFolder=if($cfg.Mode -eq 'Backup'){$cfg.WorkingTarget}else{[System.IO.Path]::Combine($cfg.Documents,'usersbackup_RestoreReports')}
        [void][System.IO.Directory]::CreateDirectory($reportFolder)
        $script:reportPath=[System.IO.Path]::Combine($reportFolder,('usersbackup_{0}_rapor_{1:yyyyMMdd_HHmmss}.txt' -f $cfg.Mode,$end))
        [System.IO.File]::WriteAllLines($script:reportPath,$txt,[System.Text.UTF8Encoding]::new($true))
    }catch{Event 'State' ('TXT rapor kaydedilemedi: '+$_.Exception.Message)}
    $events.Enqueue([pscustomobject]@{Kind='Finished';Text=$script:state;Done=$script:done;Total=$script:total;Copied=$script:copied;Skipped=$script:skipped;Failed=$script:failed;Report=$script:reportPath})
}
'@

function SetBusy([bool]$running){
    $script:Busy=$running
    $close.Enabled=$true
    $tabs.Enabled=-not $running
    $start.Enabled=-not $running
    $close.Text=if($running){'Durdur'}else{'Kapat'}
}
function PopulateRestore([string]$source){
    $restoreList.Items.Clear()
    $manifestPath=[System.IO.Path]::Combine($source,'backup_manifest.json')
    if(-not [System.IO.File]::Exists($manifestPath)){
        Message 'Bu klasörde backup_manifest.json bulunamadı. Geçerli bir usersbackup v3 yedeği seç.' 'Geçersiz yedek' 'Warning';return $false
    }
    try{
        $meta=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if($meta.FormatVersion -ne 3){throw 'Manifest sürümü v3 değil.'}
        if($meta.Status -eq 'Eksik'){
            $answer = [System.Windows.Forms.MessageBox]::Show(
                'Bu yedek yarıda kalmış olabilir. Bazı dosyalar eksik olabilir. Yine de görünen dosyalardan geri yüklemek istiyor musun?',
                'Eksik yedek uyarısı','YesNo','Warning')
            if($answer -ne 'Yes'){return $false}
        }
        $script:restoreMeta=$meta
        $restoreInfo.Text=('Kaynak kullanıcı: {0}  |  Tarih: {1}  |  Durum: {2}' -f $meta.Account,$meta.CreatedAt,$meta.Status)
        $labels=@{Desktop='Masaüstü';Downloads='İndirilenler';Documents='Belgeler';Pictures='Resimler';Videos='Videolar';Music='Müzik';CustomFolders='Özel klasörler';BrowserBookmarks='Tarayıcı favorileri';Outlook='Outlook PST';Drivers='INF sürücü paketleri';ProgramInventory='Program envanteri'}
        foreach($key in @('Desktop','Downloads','Documents','Pictures','Videos','Music','CustomFolders','BrowserBookmarks','Outlook','Drivers','ProgramInventory')){
            if([System.IO.Directory]::Exists([System.IO.Path]::Combine($source,$key))){
                $obj=[pscustomobject]@{Key=$key;Display=$labels[$key]}
                [void]$restoreList.Items.Add($obj,($key -notin @('Drivers','BrowserBookmarks')))
            }
        }
        $restorePath.Text=$source
        return $true
    }catch{Message ('Manifest okunamadı: '+$_.Exception.Message) 'Yedek okuma hatası' 'Error';return $false}
}
$chooseRestore.add_Click({
    $pick=New-Object System.Windows.Forms.FolderBrowserDialog
    $pick.Description='D:\BACKUP\kullaniciadi gibi, v3 yedek klasörünü seç'
    $pick.ShowNewFolderButton=$false
    if($pick.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK){return}
    [void](PopulateRestore $pick.SelectedPath)
})
$tabs.add_SelectedIndexChanged({
    if($tabs.SelectedIndex -eq 0){$start.Text='Yedeklemeyi Başlat'}else{$start.Text='Geri Yüklemeyi Başlat'}
})

$timer=New-Object System.Windows.Forms.Timer
$timer.Interval=180
$timer.add_Tick({
    if(-not $script:Queue){return}
    $msg=$null;$i=0
    while($i -lt 250 -and $script:Queue.TryDequeue([ref]$msg)){
        $i++
        switch([string]$msg.Kind){
            'Progress'{
                $status.Text=[string]$msg.Text
                $pct=0;if([long]$msg.Total -gt 0){$pct=[int][Math]::Min(100,[Math]::Floor(100*[double]$msg.Done/[double]$msg.Total))}
                $progress.Style='Continuous';$progress.Value=[Math]::Max(0,$pct);$percentage.Text=$pct.ToString()+'%'
            }
            'Driver' {$status.Text=[string]$msg.Text;$progress.Style='Marquee';$percentage.Text='...'}
            'Finished' {
                $script:Finished=$msg
                $script:LastReport=[string]$msg.Report;$report.Enabled=[bool]$script:LastReport
                $progress.Style='Continuous'
                if($msg.Text -in @('Tamamlandı','Uyarılarla tamamlandı')){$progress.Value=100;$percentage.Text='100%'}
                $status.Text=('{0} | Kopya: {1}, atlanan: {2}, uyarı: {3}' -f $msg.Text,$msg.Copied,$msg.Skipped,$msg.Failed)
            }
            default{$status.Text=[string]$msg.Text}
        }
        $msg=$null
    }
    if($script:Busy -and $script:Handle -and $script:Handle.IsCompleted -and $script:Queue.IsEmpty){
        try{[void]$script:Worker.EndInvoke($script:Handle)}catch{$status.Text='Arka plan hatası: '+$_.Exception.Message}
        if(-not $script:Finished){$status.Text='Arka plan işlemi beklenmedik şekilde durdu.'}
        $script:Worker.Dispose();$script:WorkerRS.Dispose();$script:Cancel.Dispose()
        $script:Worker=$null;$script:WorkerRS=$null;$script:Handle=$null;$script:Cancel=$null;$script:Finished=$null
        SetBusy $false
    }
})
$timer.Start()

$start.add_Click({
    if($script:Busy){return}
    $mode=if($tabs.SelectedIndex -eq 0){'Backup'}else{'Restore'}
    $config=[pscustomobject]@{
        Mode=$mode;Account=$script:Identity.Account;Username=$script:Identity.Username;Sid=$script:Identity.Sid
        LocalAppData=$env:LOCALAPPDATA;RoamingAppData=$env:APPDATA;Documents=[string]$script:Known['Documents']
        Known=$script:Known;WorkingTarget=$null;SourceRoot=$null;Folders=@();RestoreItems=@()
        Browsers=$false;Outlook=$false;Drivers=$false;Programs=$false;Conflict='Skip';DirectBrowser=$false
    }
    if($mode -eq 'Backup'){
        if(-not $diskBox.SelectedItem){Message 'Yedekleme diskini seç.';return}
        $config.WorkingTarget=[System.IO.Path]::Combine([string]$diskBox.SelectedItem.Root,'BACKUP',$script:Identity.Username)
        $chosen=New-Object 'System.Collections.Generic.List[object]'
        foreach($f in $folderList.CheckedItems){
            if(-not [System.IO.Directory]::Exists([string]$f.Source)){Message ('Klasör bulunamadı: '+$f.Source);return}
            if((PathWithin $config.WorkingTarget $f.Source) -or (PathWithin $f.Source $config.WorkingTarget)){
                Message ('Kaynak ile hedef iç içe olamaz: '+$f.Source) 'Hatalı klasör seçimi' 'Warning';return
            }
            $chosen.Add([pscustomobject]@{Name=[string]$f.Name;Kind=[string]$f.Kind;Source=[string]$f.Source})
        }
        $config.Folders=@($chosen.ToArray())
        $config.Browsers=$cbBrowser.Checked;$config.Outlook=$cbOutlook.Checked
        $config.Drivers=$cbDrivers.Checked;$config.Programs=$cbPrograms.Checked
        if($chosen.Count -eq 0 -and -not ($config.Browsers -or $config.Outlook -or $config.Drivers -or $config.Programs)){
            Message 'En az bir klasör veya ek yedek modülü seç.';return
        }
        if($config.Drivers){
            $c=[System.Windows.Forms.MessageBox]::Show('INF paketlerini dışa aktarmak Windows yönetici onayı isteyebilir. UAC reddedilirse diğer yedekler yine alınır. Devam?', 'INF sürücü yedekleme','YesNo','Warning')
            if($c -ne 'Yes'){return}
        }
        if([System.IO.Path]::GetPathRoot($config.WorkingTarget) -eq [System.IO.Path]::GetPathRoot([Environment]::GetFolderPath('UserProfile'))){
            $ans=[System.Windows.Forms.MessageBox]::Show('Hedef disk Windows profil diskiyle aynı. Disk bozulursa yedek de kaybolabilir. Devam edilsin mi?','Aynı disk','YesNo','Warning')
            if($ans -ne 'Yes'){return}
        }
    }else{
        $root=$restorePath.Text
        if(-not $root -or -not [System.IO.File]::Exists([System.IO.Path]::Combine($root,'backup_manifest.json'))){Message 'Geçerli v3 yedeğini seç.';return}
        $keys=@($restoreList.CheckedItems|ForEach-Object {$_.Key})
        if($keys.Count -eq 0){Message 'Geri yüklenecek en az bir veri türü seç.';return}
        $config.RestoreItems=$keys;$config.SourceRoot=$root
        $config.WorkingTarget=[string]$script:Known['Documents']
        $config.Conflict=@('Skip','Rename','Overwrite')[$conflictBox.SelectedIndex]
        $config.DirectBrowser=$directBrowser.Checked
        if($config.Conflict -eq 'Overwrite'){
            $ans=[System.Windows.Forms.MessageBox]::Show('Mevcut dosyaların üzerine yazılacak. Eski kopyaları tüm dosyalar için saklayan sürüm geçmişi yoktur. Emin misin?','Üzerine yazma','YesNo','Warning')
            if($ans -ne 'Yes'){return}
        }
        if($config.DirectBrowser -and $keys -contains 'BrowserBookmarks'){
            $ans=[System.Windows.Forms.MessageBox]::Show('Chrome/Edge açık değilse aynı adlı hedef profildeki Bookmarks dosyası güncellenecek. Mevcut Bookmarks dosyasının tarihli koruma kopyası alınır; farklı profiller otomatik eşleştirilemez. Devam?', 'Tarayıcı profiline geri yükleme','YesNo','Warning')
            if($ans -ne 'Yes'){return}
        }
        foreach($key in $keys){
            if($script:Known.ContainsKey($key) -and (PathWithin ([System.IO.Path]::Combine($root,$key)) ([string]$script:Known[$key]))){
                Message 'Kaynak yedek, geri yüklenecek kullanıcı klasörünün içinde. Güvenlik için işlem yapılmadı.' 'Çakışan yol' 'Warning';return
            }
        }
    }
    try{
        $script:Queue=New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        $script:Cancel=New-Object System.Threading.CancellationTokenSource
        $script:WorkerRS=[runspacefactory]::CreateRunspace();$script:WorkerRS.ApartmentState='MTA';$script:WorkerRS.Open()
        $script:Worker=[powershell]::Create();$script:Worker.Runspace=$script:WorkerRS
        [void]$script:Worker.AddScript($engine).AddArgument($config).AddArgument($script:Queue).AddArgument($script:Cancel)
        $script:Handle=$script:Worker.BeginInvoke()
        $script:LastReport=$null;$script:Finished=$null;$report.Enabled=$false
        $progress.Style='Continuous';$progress.Value=0;$percentage.Text='0%';$status.Text='Dosyalar taranıyor...'
        SetBusy $true
    }catch{
        Message ('İşlem başlatılamadı: '+$_.Exception.Message) 'Başlatma hatası' 'Error'
        if($script:Worker){$script:Worker.Dispose()}
        if($script:WorkerRS){$script:WorkerRS.Dispose()}
        if($script:Cancel){$script:Cancel.Dispose()}
        $script:Worker=$null;$script:WorkerRS=$null;$script:Handle=$null;$script:Cancel=$null
    }
})
$close.add_Click({
    if($script:Busy){
        $script:Cancel.Cancel();$status.Text='Durduruluyor; dosya işlemi güvenli noktada sonlanacak.'
        $close.Enabled=$false
    }else{$form.Close()}
})
$report.add_Click({
    if($script:LastReport -and [System.IO.File]::Exists($script:LastReport)){
        Start-Process -FilePath 'notepad.exe' -ArgumentList ('"'+$script:LastReport+'"')
    }
})
$form.add_FormClosing({
    if($script:Busy){
        Message 'Önce Durdur butonuna basıp işlemin bitmesini bekle. Yedekleme sırasında pencere kapatılamaz.'
        $_.Cancel=$true
    }
})
[void]$form.ShowDialog()
$timer.Stop();$timer.Dispose();$form.Dispose();if($script:IconStream){$script:IconStream.Dispose()}
