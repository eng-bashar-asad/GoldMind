// gm-local-folder.js — GoldMind
// Lets a page save files straight into one folder the person picks once
// (e.g. "Pic" on their desktop) on every subsequent save, with no repeated
// download prompts, using the File System Access API.
//
// Chromium-only (Chrome/Edge) — window.showDirectoryPicker doesn't exist
// on Firefox/Safari. Callers should always check isSupported() and fall
// back to a plain <a download> when it's false, exactly like GMCamera
// falls back to the file picker when the camera isn't available.
//
// The chosen folder's handle is remembered across sessions in IndexedDB
// (a handle can't be put in localStorage/sessionStorage — it isn't plain
// JSON, only IndexedDB can store it). Read/write permission on a
// previously-granted handle is normally silent on later visits; only the
// very first pick, and any later permission that got revoked, need an
// actual user gesture — so callers should get the folder from a click
// handler when possible (e.g. inside the Save button's own handler).

var GMLocalFolder = (function () {
  'use strict';

  var DB_NAME = 'goldmind-local-folder';
  var STORE_NAME = 'handles';
  var KEY = 'photoFolder';

  function isSupported() {
    return typeof window !== 'undefined' && !!window.showDirectoryPicker;
  }

  function openDb() {
    return new Promise(function (resolve, reject) {
      var req = indexedDB.open(DB_NAME, 1);
      req.onupgradeneeded = function () { req.result.createObjectStore(STORE_NAME); };
      req.onsuccess = function () { resolve(req.result); };
      req.onerror = function () { reject(req.error); };
    });
  }

  function getSavedHandle() {
    return openDb().then(function (db) {
      return new Promise(function (resolve) {
        var tx = db.transaction(STORE_NAME, 'readonly');
        var req = tx.objectStore(STORE_NAME).get(KEY);
        req.onsuccess = function () { resolve(req.result || null); };
        req.onerror = function () { resolve(null); };
      });
    }).catch(function () { return null; });
  }

  function saveHandle(handle) {
    return openDb().then(function (db) {
      return new Promise(function (resolve) {
        var tx = db.transaction(STORE_NAME, 'readwrite');
        tx.objectStore(STORE_NAME).put(handle, KEY);
        tx.oncomplete = function () { resolve(true); };
        tx.onerror = function () { resolve(false); };
      });
    }).catch(function () { return false; });
  }

  // Opens the native folder picker so the person can choose (or create,
  // via the dialog's own "New folder") the folder to save into from now
  // on. Must be called from a direct user gesture (a click handler).
  // Resolves the handle on success, or null if unsupported/cancelled.
  function pickFolder() {
    if (!isSupported()) return Promise.resolve(null);
    return window.showDirectoryPicker({ mode: 'readwrite' })
      .then(function (handle) { return saveHandle(handle).then(function () { return handle; }); })
      .catch(function () { return null; }); // person closed the dialog without picking
  }

  function ensurePermission(handle) {
    return handle.queryPermission({ mode: 'readwrite' }).then(function (state) {
      if (state === 'granted') return true;
      return handle.requestPermission({ mode: 'readwrite' }).then(function (s) { return s === 'granted'; });
    });
  }

  // The currently configured folder, with read-write permission confirmed
  // — or null if nothing is configured yet, or permission was refused.
  function getActiveFolder() {
    return getSavedHandle().then(function (handle) {
      if (!handle) return null;
      return ensurePermission(handle).then(function (ok) { return ok ? handle : null; });
    });
  }

  function saveFile(folderHandle, file) {
    return folderHandle.getFileHandle(file.name, { create: true })
      .then(function (fileHandle) { return fileHandle.createWritable(); })
      .then(function (writable) { return writable.write(file).then(function () { return writable.close(); }); });
  }

  return {
    isSupported: isSupported,
    pickFolder: pickFolder,
    getSavedHandle: getSavedHandle,
    getActiveFolder: getActiveFolder,
    saveFile: saveFile
  };
})();
