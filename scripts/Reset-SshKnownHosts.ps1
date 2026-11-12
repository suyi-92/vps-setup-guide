& {
    $ErrorActionPreference = 'Stop'
    # 使用自定义 UserKnownHostsFile 时，将此处换成实际路径。
    $knownHosts = Join-Path $HOME '.ssh\known_hosts'

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $dialog = [System.Windows.Forms.Form]::new()
    $dialog.Text = '重置 SSH 主机密钥记录'
    $dialog.StartPosition = 'CenterScreen'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.TopMost = $true
    $dialog.AutoScaleMode = 'Font'
    $dialog.ClientSize = [System.Drawing.Size]::new(370, 116)

    $label = [System.Windows.Forms.Label]::new()
    $label.Text = '请输入要重置所有 SSH 端口记录的 IP 地址或主机名'
    $label.SetBounds(12, 12, 346, 23)

    $addressBox = [System.Windows.Forms.TextBox]::new()
    $addressBox.MaxLength = 255
    $addressBox.SetBounds(12, 38, 346, 24)

    $ok = [System.Windows.Forms.Button]::new()
    $ok.Text = '确定'
    $ok.DialogResult = 'OK'
    $ok.SetBounds(196, 76, 76, 28)

    $cancel = [System.Windows.Forms.Button]::new()
    $cancel.Text = '取消'
    $cancel.DialogResult = 'Cancel'
    $cancel.SetBounds(282, 76, 76, 28)

    $dialog.Controls.AddRange([System.Windows.Forms.Control[]]@($label, $addressBox, $ok, $cancel))
    $dialog.AcceptButton = $ok
    $dialog.CancelButton = $cancel
    $dialog.ActiveControl = $addressBox

    try {
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }
        $address = $addressBox.Text.Trim().ToLowerInvariant()
    } finally {
        $dialog.Dispose()
    }

    if ($address.Length -eq 0) {
        return
    }
    $parsedIp = $null
    if ($address -cnotmatch '\A[a-z0-9_][a-z0-9._-]*\z' -and
        ($address.Contains('[') -or -not [Net.IPAddress]::TryParse($address, [ref]$parsedIp))) {
        Write-Warning '请填写 IP 地址或主机名，例如 203.0.113.10。'
        return
    }
    if (-not (Test-Path -LiteralPath $knownHosts -PathType Leaf)) {
        Write-Host "找不到记录文件 $knownHosts"
        return
    }

    # Latin-1 将每个字节映射到一个字符，可原样写回注释及换行。
    $encoding = [Text.Encoding]::GetEncoding(28591)
    $original = $encoding.GetString([IO.File]::ReadAllBytes($knownHosts))
    $addresses = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [void]$addresses.Add($address)
    $portPrefix = "[$address]:"
    for ($port = 1; $port -le 65535; $port++) {
        [void]$addresses.Add($portPrefix + $port)
    }

    $hashCandidates = [Collections.Generic.List[byte[]]]::new()
    if ($original.Contains('|1|')) {
        foreach ($candidate in $addresses) {
            $hashCandidates.Add([Text.Encoding]::UTF8.GetBytes($candidate))
        }
    }

    function Test-TargetSshEntry([string]$entry) {
        if (-not $entry.StartsWith('|1|', [StringComparison]::Ordinal)) {
            return $addresses.Contains($entry)
        }

        # OpenSSH 的 |1| 记录保存盐及对应地址的 HMAC-SHA1。
        $parts = $entry.Split([char]'|')
        if ($parts.Length -ne 4 -or $parts[2] -cnotmatch '\A[A-Za-z0-9+/]{27}=\z' -or
            $parts[3] -cnotmatch '\A[A-Za-z0-9+/]{27}=\z') {
            return $false
        }

        $salt = [Convert]::FromBase64String($parts[2])
        $hmac = [Security.Cryptography.HMACSHA1]::new($salt)
        try {
            foreach ($candidate in $hashCandidates) {
                $hash = [Convert]::ToBase64String($hmac.ComputeHash($candidate))
                if ($hash -ceq $parts[3]) {
                    return $true
                }
            }
        } finally {
            $hmac.Dispose()
        }
        return $false
    }

    $filtered = [Text.StringBuilder]::new($original.Length)
    foreach ($line in [regex]::Matches($original, '[^\n]*\n|[^\n]+$')) {
        $record = [regex]::Match($line.Value, '^([ \t]*)([^#@ \t\r\n][^ \t\r\n]*)(?=[ \t])')
        if (-not $record.Success) {
            [void]$filtered.Append($line.Value)
            continue
        }

        $remaining = @(
            foreach ($entry in $record.Groups[2].Value.Split([char]',')) {
                if (-not (Test-TargetSshEntry $entry)) {
                    $entry
                }
            }
        ) -join ','
        if ($remaining.Length -gt 0) {
            [void]$filtered.Append($record.Groups[1].Value)
            [void]$filtered.Append($remaining)
            [void]$filtered.Append($line.Value.Substring($record.Length))
        }
    }

    $updated = $filtered.ToString()
    if ([string]::Equals($updated, $original, [StringComparison]::Ordinal)) {
        Write-Host "没有找到 $address 的记录"
        return
    }

    $suffix = [guid]::NewGuid().ToString('N')
    $staged = "$knownHosts.tmp-$suffix"
    $backup = "$knownHosts.bak-$suffix"
    try {
        [IO.File]::WriteAllBytes($staged, $encoding.GetBytes($updated))
        $current = $encoding.GetString([IO.File]::ReadAllBytes($knownHosts))
        if (-not [string]::Equals($current, $original, [StringComparison]::Ordinal)) {
            throw '记录文件已变化，请重新运行脚本。'
        }
        [IO.File]::Replace($staged, $knownHosts, $backup)
    } finally {
        [IO.File]::Delete($staged)
    }

    Write-Host "已清理 $address 的 SSH 主机密钥记录。"
    Write-Host "备份位置 $backup"
}
