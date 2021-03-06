{ipcRenderer} = require 'electron'
toWav = require 'audiobuffer-to-wav'
xhr = require 'xhr'

$home = document.querySelector '.home'
$script = document.querySelector '.script'
$import = document.querySelector '.import'
$textline = document.querySelector '.textline'
$shuttle = document.querySelector '.shuttle'
$index = document.querySelector '.index'
$appcontrols = document.querySelector '.appcontrols'
$recstop = document.querySelector '.recstop'
$retry = document.querySelector '.retry'
$play = document.querySelector '.play'
$indexnumber = document.querySelector '.index .number'
$btnback = document.querySelector '.back'
$btnnext = document.querySelector '.next'
$btnnextrec = document.querySelector '.nextrec'
$outputdir = document.querySelector '.outputdir label'
$inputs = document.querySelector '.inputs'
$directory = document.querySelector '.outputdir label'
$main = document.querySelector '.main'
$prependStr = document.querySelector 'input.prependStr'

myscript = []
directory = null
prependStr = ''
recording = false
playing = false
currentIndex = 0
current = {}
last = {}
inputDevices = []
selectedDevice = 0
audio = null
mediaRecorder = null
wavPlayer = null
source = null
analyser = null
chunks = []
stopFn = null
viz = null

removeClass = (elem, name) ->
  re = new RegExp '\\s*\\b' + name + '\\b'
  elem.className = elem.className.replace re, ''
addClass = (elem, name) ->
  removeClass elem, name
  elem.className += ' ' if elem.className
  elem.className += name

updateView = ->
  if myscript and myscript.length
    removeClass $script, 'hidden'
    addClass $home, 'hidden'
    $directory.innerHTML = if directory then directory else 'Please select a folder...'
    $prependStr.value = prependStr
    $prependStr.disabled = recording
    if directory then removeClass($main, 'disabled') else addClass($main, 'disabled')
    $recstop.innerHTML = if recording then 'Stop' else 'Record'
    $play.innerHTML = if playing then 'Stop' else 'Play'
    $textline.innerHTML = current.text if current.text
    $indexnumber.innerHTML = current.filename + ' / ' + last.filename if current.filename
    $recstop.disabled = playing
    $retry.disabled = not recording
    $play.disabled = recording
    if not current.wav then $play.disabled = true
    ###
    buttons = $appcontrols.querySelectorAll 'button'
    for button in buttons
      if playing or recording
        button.disabled = true
      else
        button.disabled = false
    ###
    $btnback.disabled = currentIndex is 0
    $btnnext.disabled = currentIndex >= myscript.length - 1
    $btnnextrec.disabled = currentIndex >= myscript.length - 1
  else
    addClass $script, 'hidden'
    removeClass $home, 'hidden'
      
      
updateView()

renderDevices = ->
  html = ''
  for device, i in inputDevices
    html += '<option value="' + i + '"' + (if +selectedDevice is i then ' selected' else '') + '>' + device.label + '</option>'
  $inputs.innerHTML = html
  
setupAudio = ->
  stream = await navigator.mediaDevices.getUserMedia
    audio:
      deviceId:
        exact: inputDevices[selectedDevice].deviceId
  audio = new AudioContext()
  source = audio.createMediaStreamSource stream
  analyser = audio.createAnalyser()
  dest = audio.createMediaStreamDestination()
  source.connect analyser
  analyser.connect dest
  analyser.fftSize = 2048
  viz = require('./viz') analyser
  mediaRecorder = new MediaRecorder dest.stream
  mediaRecorder.ondataavailable = (e) ->
    chunks.push e.data
  mediaRecorder.onstop = (e) ->
    blob = new Blob chunks,
      type: 'audio/wav'
    current.wav = blob
    chunks = []
    
    xhr
      uri: URL.createObjectURL current.wav
      responseType: 'arraybuffer'
    , (err, body, response) ->
      audio.decodeAudioData response, (buffer) ->
        wav = toWav buffer
        current.wav = wav
        updateView()
        output = []
        for line in myscript
          output.push
            filename: prependStr + line.filename
            text: line.text
        ipcRenderer.send 'rendered', 
          directory: directory
          filename: prependStr + current.filename
          buffer: Buffer.from wav
          script: output
        stopFn?()

init = ->
  devices = await navigator.mediaDevices.enumerateDevices()
  selectedDevice = 0
  inputDevices = []
  for device in devices
    if device.kind is 'audioinput'
      inputDevices.push device
  renderDevices()
  setupAudio()
init()

waitForRender = ->
  new Promise (resolve) ->
    stopFn = ->
      resolve()
      stopFn = null
    
goTo = (index, autostart) ->
  if recording
    recording = false
    mediaRecorder.stop()
    await waitForRender()
  current = myscript[index]
  currentIndex = index
  ipcRenderer.send 'fetchWave',
    directory: directory
    filename: prependStr + current.filename
  if autostart
    recording = true
    chunks = []
    mediaRecorder.start()
  updateView()

ipcRenderer.on 'scriptImported', (app, scr) ->
  myscript = scr
  last = myscript[myscript.length - 1]
  goTo 0
  
ipcRenderer.on 'wave', (app, wav) ->
  current.wav = wav.response.buffer
  updateView()
  
ipcRenderer.on 'directorySelected', (app, obj) ->
  directory = obj.dir
  prependStr = obj.prependStr
  updateView()
  goTo 0
  
draw = ->
  requestAnimationFrame draw
  viz.draw() if viz
draw()

module.exports =
  selectDirectory: ->
    ipcRenderer.send 'selectDirectory', myscript
  selectInputDevice: (val) ->
    selectedDevice = +val
    setupAudio()
  setPrependString: (str) ->
    prependStr = str
  importScript: ->
    ipcRenderer.send 'importScript'
  recstop: ->
    if recording
      #save recording
      recording = false
      mediaRecorder.stop()
    else
      recording = true
      chunks = []
      mediaRecorder.start()
    updateView()
  retry: ->
    if recording
      recording = false
      updateView()
      mediaRecorder.stop()
      await waitForRender()
      setTimeout ->
        recording = true
        chunks = []
        mediaRecorder.start()
        updateView()
      , 100
  play: ->
    if playing
      playing = false
      wavPlayer.stop() if wavPlayer
    else
      playing = true
      wavPlayer = audio.createBufferSource()
      wavPlayer.connect audio.destination
      res = await audio.decodeAudioData current.wav.slice(0)
      wavPlayer.buffer = res
      wavPlayer.start()
      wavPlayer.onended = ->
        playing = false
        updateView()
    updateView()
  back: ->
    goTo currentIndex - 1
  next: ->
    goTo currentIndex + 1
  nextAndStartRecording: ->
    goTo currentIndex + 1, true
  finish: ->
    if recording
      recording = false
      mediaRecorder.stop()
      await waitForRender()
      updateView()
    if confirm 'Are you sure?'
      myscript = []
      directory = null
      recording = false
      playing = false
      currentIndex = 0
      current = {}
      last = {}
      updateView()
