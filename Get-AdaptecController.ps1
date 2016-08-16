Function Get-AdaptecController
{
    <#
        .NAME
            Get-AdaptecController

        .SYNOPSIS
            This Function Returns Controller Information. It Leverages The ARCCONF Utility

        .DESCRIPTION
            This Function Returns Controller Information. It Leverages The ARCCONF Utility

        .NOTES
            Author          : David Pedley
            Version         : 1.00
        
            Version History:
            1.00            - Initial Release

        .EXAMPLE
            #This Example Will Use ARCCONF To Return Controller Details For All Supported Adapted RAID Controllers
            Get-AdaptecController -ARCCONFPath C:\ARCCONF.EXE
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)][String]$ARCCONFPath, #Path To The ARCCONF.EXE
        [String]$VerboseDateFormat = 'yyyy-MM-dd HH.mm:ss' #This Specifies The Date Format For The Verbose Logging
    )

    Try
    {
        Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Using ARCCONF.EXE To Return Controller Information`r`n"
        #Use ARCCONF.EXE To Return Controller Information
        [String[]]$Controllers = & $ARCCONFPath GETVERSION 
    }
    Catch
    {
        Write-Error "ARCCONF.EXE Failed To Execute"
        Throw $_.Exception
    }

    #These Next Two ForEach Loops Aim To Product An Array That Contains The Indexed Line locations (Start And End) Of Each Controller In The $Controllers ARCCONF Output
    #To Do This (So Each Controller Can Be Evaluated And Dealt With Separately) We Need To Split Them out
    #We Do This In The Next Few Lines By Identifying The 'Controller #' Lines In The ARCCONF Output (Indicating The Beginning Of A Section Showing Controller Details)
    #We Then Identify The Line Number That The 'Controller #' Begins At And Work Out The End Line (By Looking At The Next Occurrance Of 'Controller #' And Noting The Line Number)
    Try
    {
        #Here The Idea Is To Identify The Line Numbers That Each Controller ID (Controller) Is Represented In The ARCCONF Output
        #Create A Counter To Identify Line Numbers
        [Int]$Counter = 0
        #We Iterate Though Each Line In The ARCCONF Output
        [Array]$ControllerInformation = ForEach ($Line In $Controllers)
        {
            Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Analysing Line $Counter Of ARCCONF Output To Check For Controller Details`r`n"
            #If The Line Matches 'Controller #\d+' (Controller #1) We Build An Object Including The Controller ID, Device Name And The Line Number
            If ($Line -MATCH 'Controller #\d+')
            {
                Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Found $($Line.Trim()) At Line $Counter`r`n"
                #Add The Controller Name And Line Count In The Output To The Object
                Write-Output (New-Object PSObject -Property @{ControllerText=$Line.Trim();ControllerID=[Int]([REGEX]::Match($Line, '\d+')).Value;LineStart=$Counter;LineEnd=$Null})
            }

            #Increment The Counter
            $Counter++
        }

        #Create A Counter To Identify Array Numbers
        [Int]$CurrentLineCounter = 0
        #Iterate Though The Array, Populating The LineEnd Property 
        ForEach ($Item In ($ControllerInformation | Sort-Object LineStart))
        {
            #We Calculate The Index Of The Next Item In The List
            $NextLineCounter = $CurrentLineCounter+1
            #We Set The Current Items LineEnd Value (I.E. Where The Controller Information End) To 1 Less Than LineStart Property For The Next Item In The List
            #If There Is No Next Item In The List (I.E. We Are At the End Of The List), We Set The LineEnd Value To The Total Line Count In The Original $Controllers Variable Retrieved From ARCCONF
            $Item.LineEnd = $(If ($NextLineCounter -EQ $ControllerInformation.Count) {$Controllers.Count} Else {($ControllerInformation[$NextLineCounter].Linestart)-1})
            Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Controller $($Item.ControllerText) Starts At Line $($Item.LineStart) And Ends At Line $Item.LineEnd`r`n"
            #Increment The Counter
            $CurrentLineCounter++
        }
    }
    Catch
    {
        Write-Error "Unable To Parse And Separate ARCCONF Controller Output"
        Throw $_.Exception
    }

    #Only Continue If Some Output Was Retrieved
    #We Check This By Ensurring There Is At least 1 Object In The $ControllerInformation Object
    If ($ControllerInformation.Count -GT 0)
    {
        Try
        {
            #Now We Have An Object ($ControllerInformation) Containing The Start And End Line Numbers In The $Controllers Multi-String For Each Controller We Start Promoting Properties
            #We Iterate Through The $ControllerInformation, Returning And Processing The Relevent Lines From $Controllers
            ForEach ($Controller In $ControllerInformation)
            {
                #Create A PSObject. We Will Use This To Build Up Our Object (Containing Controller Information)
                $PSObject = New-Object PSObject
                #Iterate Through Each Line In The ARCCONF Output
                ForEach ($Line In $Controllers[$Controller.LineStart..$Controller.LineEnd])
                {
                    #Now We Use Regex To Identify The Controller Information
                    If ($Line -MATCH 'Controller #\d+')
                    {
                        Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Found Controller`r`n"
                        #We Then Add Properties To The $PSObject Creating A Property.
                        $PSObject | Add-Member -Name 'ControllerID' -Value $Controller.ControllerID -MemberType NoteProperty -Force
                    }
                    #If The Line Begins With 'Firmware  ' We Continue
                    ElseIf($Line -MATCH '^Firmware\s{2}')
                    {
                        Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Found Controller Firmware Information Line '$($Line)'`r`n"
                        #We Trim WhiteSpace Off The Start Of The String
                        #We Split The Line In 2.
                        #To Do This We Use The Regex #(?s)\s{2}.*?\:\s
                        #To Explain the Above Regex...:
                        #(?s) Match The Remainder Of The Pattern - In This Case The Pattern Is '\s{2}' (2 Spaces). Make Sure This Pattern is Included In The Match
                        #.*? Continue To Match Any Character Multiple Times Until You Reach The Defined Pattern - Also Match This '\:\s' (A Colon Followed By A Space)
                        #As Ever Regex Testers Are You Friend (E.G. https://regex101.com/)
                        $SplitOutput = $Line.Trim() -SPLIT '(?s)\s{2}.*?\:\s'

                        #We Then Add Properties To The $PSObject
                        $PSObject | Add-Member -Name $($SplitOutput[0]) -Value $($SplitOutput[1]) -MemberType NoteProperty -Force

                        #This Is If You Want A Name Value Pair Rather Than Each Column Addressed Separately
                        #Write-Output (New-Object PSObject -Property @{Name=$($SplitOutput[0]);Value=$($SplitOutput[1])})
                    }
                    #If The Line Begins With 'BIOS  ' We Continue
                    ElseIf($Line -MATCH '^BIOS\s{2}')
                    {
                        Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Found Controller BIOS Information Line '$($Line)'`r`n"
                        #We Trim WhiteSpace Off The Start Of The String
                        #We Split The Line In 2.
                        #To Do This We Use The Regex #(?s)\s{2}.*?\:\s
                        #To Explain the Above Regex...:
                        #(?s) Match The Remainder Of The Pattern - In This Case The Pattern Is '\s{2}' (2 Spaces). Make Sure This Pattern is Included In The Match
                        #.*? Continue To Match Any Character Multiple Times Until You Reach The Defined Pattern - Also Match This '\:\s' (A Colon Followed By A Space)
                        #As Ever Regex Testers Are You Friend (E.G. https://regex101.com/)
                        $SplitOutput = $Line.Trim() -SPLIT '(?s)\s{2}.*?\:\s'

                        #We Then Add Properties To The $PSObject
                        $PSObject | Add-Member -Name $($SplitOutput[0]) -Value $($SplitOutput[1]) -MemberType NoteProperty -Force

                        #This Is If You Want A Name Value Pair Rather Than Each Column Addressed Separately
                        #Write-Output (New-Object PSObject -Property @{Name=$($SplitOutput[0]);Value=$($SplitOutput[1])})
                    }
                    #If The Line Begins With 'Driver  ' We Continue
                    ElseIf($Line -MATCH '^Driver\s{2}')
                    {
                        Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Found Controller Driver Information Line '$($Line)'`r`n"
                        #We Trim WhiteSpace Off The Start Of The String
                        #We Split The Line In 2.
                        #To Do This We Use The Regex #(?s)\s{2}.*?\:\s
                        #To Explain the Above Regex...:
                        #(?s) Match The Remainder Of The Pattern - In This Case The Pattern Is '\s{2}' (2 Spaces). Make Sure This Pattern is Included In The Match
                        #.*? Continue To Match Any Character Multiple Times Until You Reach The Defined Pattern - Also Match This '\:\s' (A Colon Followed By A Space)
                        #As Ever Regex Testers Are You Friend (E.G. https://regex101.com/)
                        $SplitOutput = $Line.Trim() -SPLIT '(?s)\s{2}.*?\:\s'

                        #We Then Add Properties To The $PSObject
                        $PSObject | Add-Member -Name $($SplitOutput[0]) -Value $($SplitOutput[1]) -MemberType NoteProperty -Force

                        #This Is If You Want A Name Value Pair Rather Than Each Column Addressed Separately
                        #Write-Output (New-Object PSObject -Property @{Name=$($SplitOutput[0]);Value=$($SplitOutput[1])})
                    }
                }

                Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Generating The Results...`r`n"
                #Finally We Write Out The Object
                Write-Output $PSObject
            }
        }
        Catch
        {
            Write-Error "Unable To Parse ARCCONF Output"
            Throw $_.Exception
        }
    }
    Else #If We Have No ARCCONF Output Throw An Error And Exit
    {
        Write-Error "Failed To Return Controller Information. Make ARCCONF Supports Your RAID Controller."
        Throw $_.Exception
    }

}