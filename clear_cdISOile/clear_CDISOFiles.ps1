$vms = Get-VM

foreach ($vm in $vms) {
    
    Get-CDDrive -VM $vm | Set-CDDrive -NoMedia

}