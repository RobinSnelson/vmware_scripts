function CreateVM {
    [CmdletBinding()]
    [Alias()]
    Param
    (
        #Path to config files
    )
    Begin {
        $domainCredentials = Get-Credential -Message "Give domain admins credentials to join domain"

        $vmwareCredentials = Get-Credential -Message "Give Vmware Credentials to connect to vCenter "

        #finds where teh script is beign ran from to add to the path for the paramater files
        $ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
        Write-verbose "Creating Environment"
        #Pulls Environment Information in, first checks to see if the file is present
        if (!(test-path -Path ("$ScriptDir/envInfo.csv"))) {
            Write-Error "Environment Information CSV file is not Present, Script will Stop"
            BREAK
        }
        else
        {
            Write-Verbose "Importing Environment Information"
            $envInfo = Import-csv -Path "$ScriptDir\envInfo.csv"
        }
        #Check for modules that are required
        if (!(Get-Module -Name VMware.VimAutomation.Core))
        {
            If(Get-Module -Name VMware.VimAutomation.Core -ListAvailable)
            {
                Write-Verbose "Vmware Module is present, Module will be loaded"
                Try
                {
                    Import-Module -name VMware.VimAutomation.Core -ErrorAction Stop
                    Write-Verbose "Module Imported"
                }
                Catch
                {
                    $errorMessage = $_.Exception.Message
                    Write-Warning "The Module VMware.VimAutomation.Core Failed to Import,Script will quit"
                    Write-Warning -Message "Error message was  === $errorMessage "
                    BREAK
                }
            }
        }
        else
        {
            Write-Verbose "Vmware Module is present and loaded"
        }

        #Pulls VM Build Information in, first checks to see if the file is present
        if (!(test-path -Path "$ScriptDir/vmBuild.csv")) {
            Write-Error "VM Build Information CSV file is not Present, Script will Stop"
            BREAK
        }
        else {
            Write-Verbose "Importing VM Build Information"
            $vminfo = Import-Csv -Path "$ScriptDir/vmBuild.csv"
        }

    } #End Begin

    Process {

        #Connect to VIserver
        Connect-VIServer $envinfo.vcenter -Credential $vmwareCredentials
        #Loop Begins here ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        foreach ($vm in $vminfo) {
            #Creates Custom Temp Spec
            #Check for an old spec first if its there remove it.
            if (Get-OSCustomizationSpec -Name vmAutoBuild -ErrorAction SilentlyContinue) {
                Remove-OSCustomizationSpec -OSCustomizationSpec vmAutoBuild -Confirm:$false
            }

            if ($vm.ostype -eq '1') {
                Write-Verbose "Creating Windows Customization "
                $custspec = New-OSCustomizationSpec -Name vmAutoBuild -OSType Windows -FullName Localadmin -OrgName Organization -NamingScheme vm -LicenseMode PerSeat -Domain "heliostech.local" -DomainCredentials $domainCredentials -ChangeSid -TimeZone '085'
            }
            elseif ($vm.ostype -eq '2') {
                Write-Verbose "Creating Linux Customization "
                #$custspec = New-OSCustomizationSpec  -OSType Linux -Domain $vminfo.domain -Name vmAutoBuild -DnsServer $vminfo.dnsserver
                $custspec = New-OSCustomizationSpec -OSType Linux -Domain $vm.domain -Name vmAutobuild -DnsServer $vm.DnsServer
            }
            $exists = $false

            #Check for VM Name on connected server--- decision point -- as the script is automated we should just kick out here and sort it after.

            if (Get-VM -Name $vm.vmName -ErrorAction SilentlyContinue) {
                Write-Warning "Virtual Machine found with matching name, vm will not be created"
                $exists = $true
            }

            if ($exists -ne $true) {
                #Add Networking to  Customization Spec.

                if ($vm.ostype -eq '1') {
                    Get-OSCustomizationNicMapping -OSCustomizationSpec $custspec | Set-OSCustomizationNicMapping -IpMode UseStaticIP -IpAddress $vm.ipaddress -SubnetMask $vm.subnetmask -DefaultGateway $vm.defaultgateway -Dns $vm.dnsserver
                }
                elseif ($vm.ostype -eq '2') {
                    Get-OSCustomizationNicMapping -OSCustomizationSpec $custspec | Set-OSCustomizationNicMapping -IpMode UseStaticIP -IpAddress $vm.ipaddress -SubnetMask $vm.subnetmask -DefaultGateway $vm.defaultgateway
                    
                }

                #Base template...check
                $template = Get-Template -Name $vm.template


                #Build Datastore .... check for availability and space
                $dataStore = Get-Datastore -Name $EnvInfo.Datastore
                

                #build VM
                New-vm -Name $vm.VMName -template $template -ResourcePool $envInfo.Cluster -Datastore $dataStore -OSCustomizationSpec $custspec

                #set CPU and Memory
                write-verbose "setting CPU and Memory"
                get-vm -name $vm.vmname | set-vm -memoryGB $vm.memory -NumCpu $vm.cores -Confirm:$false

                #Array for disks set to null-relies on template just having one disk
                $disks = $null
                #Gets The hard disk from the VM named into the variable
                $disks = Get-HardDisk -vm $vm.vmname


                if ($disks[0].CapacityGB -ge $vm.SysSize) {
                    # do nothin
                    Write-Verbose "Disk is bigger than required no action will be taken"

                }else{

                    Set-HardDisk -HardDisk $disks[0] -CapacityGB $vm.SysSize -Confirm:$false
                    }
                #Starts the VM so it can continuw to sysprep etc
                Start-VM -VM $vm.vmname

            } #If loop ends
        } #for loop ends
        #Loop Ends here +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    } # End Process

    End {
        Write-Verbose "removing OSCustomizationSpec"
        Remove-OSCustomizationSpec -Spec vmAutoBuild  -Confirm:$false
        #Disconnect from ViServer
        Write-Verbose "Disconnecting from Virtual Centre"
        Disconnect-VIServer -Server $envinfo.vcenter -Confirm:$false
    }#End End
} #End Function

CreateVM -Verbose












