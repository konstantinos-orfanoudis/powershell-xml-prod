$file = 'C:\Users\aiuser\Desktop\System_Debugger_Libary\.agents\skills\oneim-vbnet-auditor\tests\Oneim.VbNet.Auditor.Tests.ps1'
$content = Get-Content -LiteralPath $file -Raw -Encoding UTF8

# Fix Assert-True: (($findings | Where-Object { -> (@($findings | Where-Object {
$content = $content -replace '\(\(\$findings \| Where-Object \{', '(@($findings | Where-Object {'

# Fix Assert-Equal -Actual: ($findings | Where-Object { -> @($findings | Where-Object {
$content = $content -replace 'Actual \(\$findings \| Where-Object \{', 'Actual @($findings | Where-Object {'

Set-Content -LiteralPath $file -Value $content -Encoding UTF8 -NoNewline
Write-Host "Done"
