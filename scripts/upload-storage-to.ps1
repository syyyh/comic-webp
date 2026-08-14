[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [string]$FileName,

    [string]$ContentType = 'application/octet-stream',

    [string]$ApiBase = 'https://storage.to/api'
)

$ErrorActionPreference = 'Stop'

function Invoke-StorageApi {
    param(
        [Parameter(Mandatory = $true)] [string]$Endpoint,
        [Parameter(Mandatory = $true)] [hashtable]$Body,
        [Parameter(Mandatory = $true)] [string]$VisitorToken
    )

    $response = Invoke-WebRequest `
        -Uri ($ApiBase.TrimEnd('/') + $Endpoint) `
        -Method Post `
        -Headers @{
            'Accept' = 'application/json'
            'User-Agent' = 'comic-webp-storage-uploader/1.0'
            'X-Visitor-Token' = $VisitorToken
        } `
        -ContentType 'application/json' `
        -Body ($Body | ConvertTo-Json -Compress)

    $json = $response.Content | ConvertFrom-Json
    if ($json.success -eq $false) {
        throw "storage.to $Endpoint failed: $($response.Content)"
    }
    return $json
}

function Send-PresignedPut {
    param(
        [Parameter(Mandatory = $true)] [string]$Uri,
        [Parameter(Mandatory = $true)] [System.IO.Stream]$Stream,
        [Parameter(Mandatory = $true)] [long]$Length,
        [hashtable]$Headers = @{}
    )

    $client = [System.Net.Http.HttpClient]::new()
    $request = [System.Net.Http.HttpRequestMessage]::new(
        [System.Net.Http.HttpMethod]::Put,
        $Uri
    )
    $content = [System.Net.Http.StreamContent]::new($Stream)
    $content.Headers.ContentLength = $Length

    foreach ($header in $Headers.GetEnumerator()) {
        if ($header.Key -in @('Content-Type', 'Content-Length')) {
            $content.Headers.TryAddWithoutValidation($header.Key, [string]$header.Value) | Out-Null
        } else {
            $request.Headers.TryAddWithoutValidation($header.Key, [string]$header.Value) | Out-Null
        }
    }

    $request.Content = $content
    try {
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $responseBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw "R2 PUT failed with HTTP $([int]$response.StatusCode): $responseBody"
        }

        $etag = $null
        if ($response.Headers.ETag) {
            $etag = $response.Headers.ETag.Tag
        }
        if (-not $etag -and $response.Headers.Contains('ETag')) {
            $etag = ($response.Headers.GetValues('ETag') | Select-Object -First 1)
        }
        return $etag
    } finally {
        $request.Dispose()
        $client.Dispose()
    }
}

function Convert-ToHeaderTable {
    param([object]$Headers)

    $table = @{}
    if ($null -eq $Headers) { return $table }
    foreach ($property in $Headers.PSObject.Properties) {
        $table[$property.Name] = [string]$property.Value
    }
    return $table
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "找不到文件：$Path"
}

$file = Get-Item -LiteralPath $Path
$size = [long]$file.Length
if ([string]::IsNullOrWhiteSpace($FileName)) {
    $FileName = $file.Name
}
if ([string]::IsNullOrWhiteSpace($ContentType)) {
    $ContentType = 'application/octet-stream'
}

$visitorToken = $env:STORAGE_TO_VISITOR_TOKEN
if ([string]::IsNullOrWhiteSpace($visitorToken)) {
    $visitorToken = ([guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N'))
}

Write-Host "准备上传 $FileName（$size bytes）..."
$init = Invoke-StorageApi '/upload/init' @{
    filename = $FileName
    content_type = $ContentType
    size = $size
} $visitorToken

$uploadType = if ($init.type) { [string]$init.type } else { [string]$init.upload_type }
$r2Key = $init.r2_key

if ($uploadType -eq 'single' -and $init.upload_url) {
    $stream = [System.IO.File]::OpenRead($file.FullName)
    try {
        [void](Send-PresignedPut `
            -Uri $init.upload_url `
            -Stream $stream `
            -Length $size `
            -Headers (Convert-ToHeaderTable $init.headers))
    } finally {
        $stream.Dispose()
    }
} elseif ($uploadType -eq 'multipart' -and $init.upload_id) {
    $partSize = [long]$init.part_size
    $totalParts = [int]$init.total_parts
    $initialUrls = @{}
    if ($init.initial_urls) {
        foreach ($property in $init.initial_urls.PSObject.Properties) {
            $initialUrls[[int]$property.Name] = [string]$property.Value
        }
    }

    $completed = [System.Collections.Generic.List[object]]::new()
    for ($partNumber = 1; $partNumber -le $totalParts; $partNumber++) {
        if (-not $initialUrls.ContainsKey($partNumber)) {
            $missing = @($partNumber..$totalParts)
            $more = Invoke-StorageApi '/upload/parts' @{
                upload_id = $init.upload_id
                part_numbers = $missing
            } $visitorToken
            foreach ($part in $more.part_urls) {
                $initialUrls[[int]$part.partNumber] = [string]$part.url
            }
        }

        $offset = ([long]($partNumber - 1)) * $partSize
        $length = [Math]::Min($partSize, $size - $offset)
        $stream = [System.IO.File]::OpenRead($file.FullName)
        try {
            $stream.Position = $offset
            $etag = Send-PresignedPut `
                -Uri $initialUrls[$partNumber] `
                -Stream $stream `
                -Length $length
        } finally {
            $stream.Dispose()
        }
        if ([string]::IsNullOrWhiteSpace($etag)) {
            throw "分片 $partNumber 没有返回 ETag"
        }
        $completed.Add(@{ partNumber = $partNumber; etag = $etag })
        Write-Host "已上传分片 $partNumber / $totalParts"
    }

    [void](Invoke-StorageApi '/upload/complete-multipart' @{
        upload_id = $init.upload_id
        parts = $completed
    } $visitorToken)
} else {
    throw "storage.to 返回了不支持的初始化结果：$($init | ConvertTo-Json -Compress)"
}

$confirmed = Invoke-StorageApi '/upload/confirm' @{
    filename = $FileName
    size = $size
    content_type = $ContentType
    r2_key = $r2Key
} $visitorToken

$url = $confirmed.file.url
if ([string]::IsNullOrWhiteSpace($url)) {
    throw "上传成功但没有拿到分享链接：$($confirmed | ConvertTo-Json -Compress)"
}

Write-Host "上传完成：$url" -ForegroundColor Green
Write-Output $url
