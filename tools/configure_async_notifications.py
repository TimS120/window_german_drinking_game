#!/usr/bin/env python3
"""Generate public Firebase client resources, never server credentials."""
import json
from pathlib import Path
from xml.sax.saxutils import escape
root = Path(__file__).resolve().parent.parent
config = json.loads((root / 'firebase-options.json').read_text())
android = {'google_app_id': config['FIREBASE_ANDROID_APP_ID'], 'gcm_defaultSenderId': config['FIREBASE_MESSAGING_SENDER_ID'], 'google_api_key': config['FIREBASE_API_KEY'], 'project_id': config['FIREBASE_PROJECT_ID']}
path = root / 'app/android/app/src/main/res/values/firebase_config.xml'
path.write_text('<resources>\n' + ''.join(f'  <string name="{key}" translatable="false">{escape(value)}</string>\n' for key, value in android.items()) + '</resources>\n')
web = {'apiKey': config['FIREBASE_WEB_API_KEY'], 'appId': config['FIREBASE_WEB_APP_ID'], 'messagingSenderId': config['FIREBASE_MESSAGING_SENDER_ID'], 'projectId': config['FIREBASE_PROJECT_ID']}
(root / 'app/web/firebase-notifications-config.js').write_text('firebase.initializeApp(' + json.dumps(web) + ');\n')
print('Generated public Android and browser notification configuration.')
