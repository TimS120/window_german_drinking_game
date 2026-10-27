/* Same SDK version as firebase_core_web. Only public client config is imported. */
importScripts('https://www.gstatic.com/firebasejs/13.1.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/13.1.0/firebase-messaging-compat.js');
importScripts('/firebase-notifications-config.js');
firebase.messaging();
