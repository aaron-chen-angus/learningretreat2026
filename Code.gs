/**
 * Learning Retreat 2026 — audience voting backend
 * ------------------------------------------------
 * Receives votes from https://aaron-chen-angus.github.io/learningretreat2026/
 * and writes each one as a row in the matching tab of this Google Sheet.
 *
 * Tabs (created automatically by setupSheets):
 *   BalanceVision, SilverHYROX, CognitiveChallenge, MiloAdventure, MetacognitivePrompt
 *
 * Deploy as: Web app | Execute as: Me | Who has access: Anyone
 */

const TIMEZONE = 'Asia/Singapore';

const APP_HEADERS = [
  'receivedAt', 'timestamp', 'participantId', 'device', 'app', 'questionId',
  'selected', 'selectedText', 'correctAnswer', 'isCorrect'
];

const META_HEADERS = [
  'receivedAt', 'timestamp', 'participantId', 'device',
  'hospitality', 'hospitalityCorrect',
  'appliedScience', 'appliedScienceCorrect',
  'tamd', 'tamdCorrect',
  'business', 'businessCorrect',
  'answered', 'score'
];

const TABS = {
  BalanceVision: APP_HEADERS,
  SilverHYROX: APP_HEADERS,
  CognitiveChallenge: APP_HEADERS,
  MiloAdventure: APP_HEADERS,
  MetacognitivePrompt: META_HEADERS
};

/** Receives a vote from the deck. */
function doPost(e) {
  const lock = LockService.getScriptLock();
  try {
    lock.waitLock(20000); // many phones may submit at the same moment
    const data = JSON.parse(e.postData.contents);
    const tabName = data.sheet;
    if (!TABS[tabName]) {
      return json_({ status: 'error', message: 'Unknown sheet: ' + tabName });
    }
    const sheet = getOrCreateTab_(tabName);
    data.receivedAt = Utilities.formatDate(new Date(), TIMEZONE, 'yyyy-MM-dd HH:mm:ss');

    // Map by header name, so column order in the sheet never matters.
    const headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
    const row = headers.map(function (h) {
      const v = data[h];
      return (v === undefined || v === null) ? '' : v;
    });
    sheet.appendRow(row);
    return json_({ status: 'ok', sheet: tabName });
  } catch (err) {
    return json_({ status: 'error', message: String(err) });
  } finally {
    lock.releaseLock();
  }
}

/** Health check: open the /exec URL in a browser to confirm it is live. */
function doGet() {
  return json_({ status: 'ok', message: 'Learning Retreat 2026 voting endpoint is running.' });
}

/** RUN ONCE: creates the 5 tabs with bold, frozen header rows. */
function setupSheets() {
  Object.keys(TABS).forEach(getOrCreateTab_);
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const blank = ss.getSheetByName('Sheet1');
  if (blank && blank.getLastRow() === 0 && ss.getSheets().length > 1) ss.deleteSheet(blank);
  SpreadsheetApp.getUi().alert('Done: 5 tabs are ready.');
}

/** Adds one sample row to every tab, to prove writing works. */
function testWrite() {
  const base = { timestamp: new Date().toISOString(), participantId: 'P-TEST', device: 'desktop' };
  ['BalanceVision', 'SilverHYROX', 'CognitiveChallenge', 'MiloAdventure'].forEach(function (t) {
    doPost({ postData: { contents: JSON.stringify(Object.assign({}, base, {
      sheet: t, app: t, questionId: 'TEST', selected: 'A', selectedText: 'Test row', correctAnswer: 'A', isCorrect: true
    })) } });
  });
  doPost({ postData: { contents: JSON.stringify(Object.assign({}, base, {
    sheet: 'MetacognitivePrompt', hospitality: 'B', hospitalityCorrect: true, appliedScience: 'B', appliedScienceCorrect: true,
    tamd: 'A', tamdCorrect: false, business: 'A', businessCorrect: true, answered: 4, score: 3
  })) } });
  SpreadsheetApp.getUi().alert('Test rows written to all 5 tabs.');
}

/** Deletes all responses but keeps the header rows. Run before the live session. */
function clearResponses() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  Object.keys(TABS).forEach(function (t) {
    const sh = ss.getSheetByName(t);
    if (sh && sh.getLastRow() > 1) sh.deleteRows(2, sh.getLastRow() - 1);
  });
  SpreadsheetApp.getUi().alert('All responses cleared. Headers kept.');
}

/** Adds a "Voting" menu to the sheet for the functions above. */
function onOpen() {
  SpreadsheetApp.getUi().createMenu('Voting')
    .addItem('1. Set up tabs', 'setupSheets')
    .addItem('2. Write test rows', 'testWrite')
    .addItem('3. Clear all responses', 'clearResponses')
    .addToUi();
}

function getOrCreateTab_(name) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sh = ss.getSheetByName(name);
  if (!sh) sh = ss.insertSheet(name);
  if (sh.getLastRow() === 0) {
    const headers = TABS[name];
    sh.getRange(1, 1, 1, headers.length).setValues([headers]).setFontWeight('bold');
    sh.setFrozenRows(1);
  }
  return sh;
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
