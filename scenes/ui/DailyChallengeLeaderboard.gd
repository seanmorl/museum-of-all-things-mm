extends Node
class_name DailyChallengeLeaderboard
## Global daily challenge leaderboard backed by a Google Apps Script web app.
## All players worldwide submit scores via HTTP POST; the top scores are
## fetched via HTTP GET and cached locally for the session.
##
## ── SETUP (one-time, ~5 minutes) ─────────────────────────────────────────────
## 1. Go to https://sheets.new  — create a blank Google Sheet.
## 2. Extensions → Apps Script → paste the script from APPS_SCRIPT_CODE below.
## 3. Click Deploy → New Deployment → Web App.
##    - Execute as: Me
##    - Who has access: Anyone
## 4. Copy the deployment URL and paste it into ENDPOINT below.
## 5. Done. The sheet auto-creates a "scores" tab and stores every submission.
##
## The Apps Script code to paste is at the bottom of this file in a comment.
## ─────────────────────────────────────────────────────────────────────────────

## !! REPLACE THIS with your deployed Apps Script URL !!
const ENDPOINT: String = "https://script.google.com/macros/s/AKfycbwb2WVoLUZUfugR3nCAUfrvNNru-rGayetQghPBQ_dtaDBEGqxSzRyfcpPuWBAvOs3S/exec"

const MAX_ENTRIES   := 10     ## how many top scores to fetch
const CACHE_SECONDS := 120.0  ## re-fetch leaderboard at most every 2 minutes

signal scores_updated(entries: Array)   ## Array of {name, time_seconds, date}
signal submit_succeeded
signal submit_failed(error: String)

var _cached_entries: Array = []
var _cache_date_key: String = ""   ## invalidate cache when date changes
var _last_fetch_time: float = -999.0
var _pending_submission: bool = false

# ── Public API ────────────────────────────────────────────────────────────────

## Submit a score. Call after the player finishes the daily challenge.
func submit_score(date_key: String, player_name: String, time_seconds: float) -> void:
	if ENDPOINT == "https://script.google.com/macros/s/YOUR_DEPLOYMENT_ID/exec":
		push_warning("DailyChallengeLeaderboard: ENDPOINT not configured — skipping submit.")
		return
	if _pending_submission:
		return
	_pending_submission = true

	var body := JSON.stringify({
		"action":   "submit",
		"date":     date_key,
		"name":     player_name.substr(0, 24),   # cap name length
		"time":     time_seconds
	})
	var headers := PackedStringArray(["Content-Type: application/json"])
	var http := HTTPRequest.new()
	http.name = "SubmitHTTP"
	add_child(http)
	http.request_completed.connect(func(result, code, _h, body_raw):
		_pending_submission = false
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			submit_failed.emit("HTTP error %d" % code)
			return
		submit_succeeded.emit()
		# Refresh leaderboard after a short delay so the new row is indexed
		await get_tree().create_timer(1.5).timeout
		fetch_scores(date_key, true)
	)
	var err := http.request(ENDPOINT, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_pending_submission = false
		submit_failed.emit("Request failed: %s" % str(err))
		http.queue_free()

## Fetch today's top scores. Returns cached data if fresh enough.
## force=true bypasses the cache.
func fetch_scores(date_key: String, force: bool = false) -> void:
	if ENDPOINT == "https://script.google.com/macros/s/YOUR_DEPLOYMENT_ID/exec":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not force and date_key == _cache_date_key \
	   and (now - _last_fetch_time) < CACHE_SECONDS:
		scores_updated.emit(_cached_entries.duplicate())
		return

	var url := "%s?action=fetch&date=%s&limit=%d" % [ENDPOINT, date_key, MAX_ENTRIES]
	var http := HTTPRequest.new()
	http.name = "FetchHTTP"
	add_child(http)
	http.request_completed.connect(func(result, code, _h, body_raw):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			return
		var text: String = body_raw.get_string_from_utf8()
		var parsed = JSON.parse_string(text)
		if not parsed is Array:
			return
		_cached_entries = parsed
		_cache_date_key = date_key
		_last_fetch_time = Time.get_ticks_msec() / 1000.0
		scores_updated.emit(_cached_entries.duplicate())
	)
	http.request(url)

## Return the most recent cached entries without a network call.
func get_cached_entries() -> Array:
	return _cached_entries.duplicate()

## Format seconds as "M:SS"
static func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]


# =============================================================================
# APPS SCRIPT CODE
# Paste this entire block into your Google Apps Script editor.
# =============================================================================
#
# function doPost(e) {
#   var data = JSON.parse(e.postData.contents);
#   if (data.action !== 'submit') return ContentService.createTextOutput('{}');
#   var sheet = getOrCreateSheet();
#   sheet.appendRow([
#     new Date().toISOString(),
#     data.date  || '',
#     data.name  || 'Anonymous',
#     Number(data.time) || 0
#   ]);
#   return ContentService
#     .createTextOutput(JSON.stringify({ok: true}))
#     .setMimeType(ContentService.MimeType.JSON);
# }
#
# function doGet(e) {
#   var p     = e.parameter;
#   var date  = p.date  || '';
#   var limit = parseInt(p.limit || '10', 10);
#   var sheet = getOrCreateSheet();
#   var rows  = sheet.getDataRange().getValues();
#   var out   = [];
#   for (var i = 1; i < rows.length; i++) {    // skip header row
#     var r = rows[i];
#     if (r[1] === date) {
#       out.push({ name: r[2], time_seconds: r[3], date: r[1] });
#     }
#   }
#   out.sort(function(a, b) { return a.time_seconds - b.time_seconds; });
#   out = out.slice(0, limit);
#   return ContentService
#     .createTextOutput(JSON.stringify(out))
#     .setMimeType(ContentService.MimeType.JSON);
# }
#
# function getOrCreateSheet() {
#   var ss    = SpreadsheetApp.getActiveSpreadsheet();
#   var sheet = ss.getSheetByName('scores');
#   if (!sheet) {
#     sheet = ss.insertSheet('scores');
#     sheet.appendRow(['timestamp', 'date', 'name', 'time_seconds']);
#   }
#   return sheet;
# }
