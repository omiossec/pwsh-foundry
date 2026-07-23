#Requires -Version 7.0

class FoundryTool {
    [string] $Name
    [string] $Description
    [hashtable] $Parameters
    [string[]] $Required
    [scriptblock] $Handler

    FoundryTool([string]$name, [string]$description, [hashtable]$parameters, [string[]]$required, [scriptblock]$handler) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [System.ArgumentException]::new(
                'Tool name cannot be null or empty.',
                'name'
            )
        }

        if ([string]::IsNullOrWhiteSpace($description)) {
            throw [System.ArgumentException]::new(
                'Tool description cannot be null or empty.',
                'description'
            )
        }

        if ($null -eq $handler) {
            throw [System.ArgumentException]::new(
                'Tool handler cannot be null.',
                'handler'
            )
        }

        $this.Parameters = if ($null -eq $parameters) { @{} } else { $parameters }
        $this.Required   = if ($null -eq $required)   { @() } else { $required }

        foreach ($key in $this.Required) {
            if (-not $this.Parameters.ContainsKey($key)) {
                throw [System.ArgumentException]::new(
                    "Required parameter '$key' is not defined in Parameters.",
                    'required'
                )
            }
        }

        $this.Name        = $name
        $this.Description = $description
        $this.Handler     = $handler
    }

    [hashtable] ToRequestObject() {
        return @{
            type     = 'function'
            function = @{
                name        = $this.Name
                description = $this.Description
                parameters  = @{
                    type       = 'object'
                    properties = $this.Parameters
                    required   = $this.Required
                }
            }
        }
    }

    # Runs the handler with the model-provided arguments. Never throws: errors are
    # returned as a string so the chat loop can hand them back to the model.
    [string] Invoke([hashtable]$arguments) {
        if ($null -eq $arguments) {
            $arguments = @{}
        }

        try {
            $result = & $this.Handler @arguments

            if ($null -eq $result) {
                return ''
            }

            if ($result -is [string]) {
                return $result
            }

            return ($result | ConvertTo-Json -Depth 10)
        }
        catch {
            return "Tool execution failed: $($_.Exception.Message)"
        }
    }
}
