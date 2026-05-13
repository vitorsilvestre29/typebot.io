param(
  [string]$ProjectName = "Fluxozap Typebot",
  [string]$Environment = "production",
  [string]$AdminEmail = "vitorcesarsilvestre2017@gmail.com"
)

$ErrorActionPreference = "Stop"

function Run-RailwayJson {
  param([string[]]$Args)
  $output = & railway @Args --json 2>$null
  if ($LASTEXITCODE -ne 0) {
    throw "railway $($Args -join ' ') failed"
  }
  if ([string]::IsNullOrWhiteSpace($output)) {
    return $null
  }
  return $output | ConvertFrom-Json
}

function Run-Railway {
  param([string[]]$Args)
  & railway @Args
  if ($LASTEXITCODE -ne 0) {
    throw "railway $($Args -join ' ') failed"
  }
}

function New-Secret32 {
  $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  -join (1..32 | ForEach-Object { $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)] })
}

Write-Host "Checking Railway login..."
Run-Railway @("whoami")

Write-Host "Creating/linking Railway project: $ProjectName"
$project = Run-RailwayJson @("init", "--name", $ProjectName)

Write-Host "Adding Postgres and Redis..."
Run-RailwayJson @("add", "--database", "postgres", "--service", "typebot-postgres") | Out-Null
Run-RailwayJson @("add", "--database", "redis", "--service", "typebot-redis") | Out-Null

Write-Host "Adding builder and viewer services..."
Run-RailwayJson @("add", "--service", "typebot-builder") | Out-Null
Run-RailwayJson @("add", "--service", "typebot-viewer") | Out-Null

Write-Host "Generating public domains..."
$builderDomain = Run-RailwayJson @("domain", "--service", "typebot-builder", "--environment", $Environment, "--port", "8080")
$viewerDomain = Run-RailwayJson @("domain", "--service", "typebot-viewer", "--environment", $Environment, "--port", "8080")

$builderUrl = "https://$($builderDomain.domain)"
$viewerUrl = "https://$($viewerDomain.domain)"
$secret = New-Secret32

Write-Host "Builder URL: $builderUrl"
Write-Host "Viewer URL:  $viewerUrl"

$commonVars = @(
  'DATABASE_URL=${{typebot-postgres.DATABASE_URL}}',
  'REDIS_URL=${{typebot-redis.REDIS_URL}}',
  "ENCRYPTION_SECRET=$secret",
  "NEXTAUTH_URL=$builderUrl",
  "NEXT_PUBLIC_VIEWER_URL=$viewerUrl",
  "NODE_OPTIONS=--no-node-snapshot"
)

Write-Host "Setting builder variables..."
Run-Railway @("variable", "set", "--service", "typebot-builder", "--environment", $Environment, "--skip-deploys", "RAILWAY_DOCKERFILE_PATH=Dockerfile.builder")
foreach ($variable in $commonVars) {
  Run-Railway @("variable", "set", "--service", "typebot-builder", "--environment", $Environment, "--skip-deploys", $variable)
}
Run-Railway @("variable", "set", "--service", "typebot-builder", "--environment", $Environment, "--skip-deploys", "ADMIN_EMAIL=$AdminEmail")
Run-Railway @("variable", "set", "--service", "typebot-builder", "--environment", $Environment, "--skip-deploys", "DISABLE_SIGNUP=true")

Write-Host "Setting viewer variables..."
Run-Railway @("variable", "set", "--service", "typebot-viewer", "--environment", $Environment, "--skip-deploys", "RAILWAY_DOCKERFILE_PATH=Dockerfile.viewer")
foreach ($variable in $commonVars) {
  Run-Railway @("variable", "set", "--service", "typebot-viewer", "--environment", $Environment, "--skip-deploys", $variable)
}

Write-Host "Deploying builder..."
Run-Railway @("up", "--service", "typebot-builder", "--environment", $Environment, "--detach", "--message", "Deploy Typebot builder for Fluxozap")

Write-Host "Deploying viewer..."
Run-Railway @("up", "--service", "typebot-viewer", "--environment", $Environment, "--detach", "--message", "Deploy Typebot viewer for Fluxozap")

Write-Host ""
Write-Host "Done. Save these values for Fluxozap:"
Write-Host "TYPEBOT_BASE_URL=$builderUrl"
Write-Host "TYPEBOT_API_URL=$builderUrl/api/v1"
Write-Host "TYPEBOT_VIEWER_URL=$viewerUrl"
Write-Host "TYPEBOT_EDITOR_TEMPLATE=/_fluxo-builder/typebots/{{typebotId}}"
Write-Host ""
Write-Host "You still need to open the builder, create/get the API key and workspace ID, then paste them in Fluxozap Integracoes."
