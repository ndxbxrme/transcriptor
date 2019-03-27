'use strict'

{app, BrowserWindow, dialog, ipcMain} = require 'electron'
{autoUpdater} = require 'electron-updater'
fs = require 'fs-extra'
url = require 'url'
path = require 'path'

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
    for line in lines
      line.replace /(\d+)\s+(.*)/, (all, filename, text) ->
        if all and filename and text
          output.push
            filename: filename
            text: text
        all
    mainWindow.webContents.send 'scriptImported', output
ipcMain.on 'selectDirectory', ->
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
  mainWindow.openDevTools()
app.on 'ready', ready
app.on 'window-all-closed', ->
  process.platform is 'darwin' or app.quit()
app.on 'activiate', ->
  mainWindow or ready()