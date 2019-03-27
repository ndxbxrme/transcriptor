'use strict'

{app, BrowserWindow, dialog, ipcMain} = require 'electron'
{autoUpdater} = require 'electron-updater'
fs = require 'fs-extra'
url = require 'url'
path = require 'path'

pad = (n, len) ->
  new Array(len - n.toString().length).fill(0).join('') + n

ipcMain.on 'importScript', ->
  results = dialog.showOpenDialog
    properties: ['openFile']
    filters: [
      name: 'TXT'
      extensions: ['txt']
    ]
  if results and results.length
    output = []
    text = await fs.readFile results[0], 'utf8'
    lines = text.split /\n/g
    i = 0
    len = lines.length.toString().length
    for line in lines
      if line and line.trim()
        output.push
          filename: pad ++i, len
          text: line
    mainWindow.webContents.send 'scriptImported', output
ipcMain.on 'selectDirectory', (win, script) ->
  results = dialog.showOpenDialog
    properties: ['openDirectory', 'createDirectory']
  if results
    mainWindow.webContents.send 'directorySelected', results[0]
ipcMain.on 'fetchWave', (win, file) ->
  if file and file.directory and file.filename and await fs.exists path.join(file.directory, file.filename + '.wav')
    mainWindow.webContents.send 'wave',
      response: await fs.readFile path.join(file.directory, file.filename + '.wav')
      details: file
ipcMain.on 'rendered', (win, current) ->
  fs.writeFile path.join(current.directory, current.filename + '.wav'), Buffer new Uint8Array current.buffer
  output = ''
  for line in current.script
    if await fs.exists path.join(current.directory, line.filename + '.wav')
      output += line.filename + '\t' + line.text + '\n'
  await fs.writeFile path.join(current.directory, 'index.txt'), output, 'utf8'

mainWindow = null
ready = ->
  autoUpdater.checkForUpdatesAndNotify()
  mainWindow = new BrowserWindow
    width: 800
    height: 600
    backgroundColor: '#222222'
    autoHideMenuBar: true
  mainWindow.on 'closed', ->
    mainWindow = null
  mainWindow.loadURL url.format
    pathname: path.join __dirname, 'index.html'
    protocol: 'file:'
    slashes: true
app.on 'ready', ready
app.on 'window-all-closed', ->
  process.platform is 'darwin' or app.quit()
app.on 'activiate', ->
  mainWindow or ready()