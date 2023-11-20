Get-ChildItem -Path "C:\Users\edarl\OneDrive\Documents\GitHub\DarlingData" -Filter "sp_*" |
Where-Object { $_.FullName -notlike "*sp_WhoIsActive*" } |
ForEach-Object { Get-ChildItem $_.FullName |  
Where-Object { $_.Name -like "sp_*" -and $_.Name -notlike "sp_Human Events Agent*" } } | 
ForEach-Object { Get-Content $_.FullName -Encoding UTF8 } | 
Set-Content -Path "$FilePath\Install-All\DarlingData.sql" -Encoding UTF8 -Force