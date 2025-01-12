function Prompt-Continue {
    param (
        [switch]$AutoContinue  # Optional parameter to bypass the prompt
    )

    if (-not $AutoContinue) {
        while ($true) {
            $continue = Read-Host "Continue Marko Test? (y/n)"
            if ($continue -eq 'y') {
                Write-Output 'You chose to continue.'
                break  # Exit the loop and proceed
            } elseif ($continue -eq 'n') {
                Write-Output 'You chose not to continue. Terminating script.'
                exit  # Terminate the entire script
            } else {
                Write-Output 'Invalid input. Please enter "y" or "n".'
            }
        }
    }
}
# Call the function 
Prompt-Continue
