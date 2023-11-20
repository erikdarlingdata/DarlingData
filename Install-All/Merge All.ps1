$FilePath = "C:\Users\edarl\OneDrive\Documents\GitHub\DarlingData"
Get-ChildItem -Path "$FilePath" -Filter "sp_*" |
Where-Object { $_.FullName -notlike "*sp_WhoIsActive*" } |
ForEach-Object { Get-ChildItem $_.FullName |  
Where-Object { $_.Name -like "sp_*" -and $_.Name -notlike "sp_Human Events Agent*" } } | 
ForEach-Object { Get-Content $_.FullName -Encoding Unicode } | 
Set-Content -Path "$FilePath\Install-All\DarlingData.sql" -Encoding Unicode -Force