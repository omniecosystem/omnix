# Creates a small synthetic qualification fixture using an installed Windows voice.
# This is test tooling, not an Omnix speech runtime or application dependency.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$fixtureDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('omnix-audio-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixtureDirectory
$fixturePath = Join-Path $fixtureDirectory 'pineapple.wav'
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
try {
    $voice = $synth.GetInstalledVoices() | Where-Object {
        $_.Enabled -and $_.VoiceInfo.Culture.TwoLetterISOLanguageName -eq 'en'
    } | Select-Object -First 1
    if ($null -eq $voice) { throw 'An installed English Windows speech voice is required for this test fixture.' }
    $synth.SelectVoice($voice.VoiceInfo.Name)
    $format = [System.Speech.AudioFormat.SpeechAudioFormatInfo]::new(
        16000,
        [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
        [System.Speech.AudioFormat.AudioChannel]::Mono
    )
    $synth.SetOutputToWaveFile($fixturePath, $format)
    $synth.Speak('The secret word is pineapple.')
} finally {
    $synth.Dispose()
}
$fixturePath
