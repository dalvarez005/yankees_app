// Push en el navegador (Firebase Cloud Messaging). Muestra el aviso cuando la
// app está cerrada o en segundo plano; tocarlo abre la app (link que manda la
// API). La versión debe coincidir con la que usa FlutterFire (firebase_core_web).
importScripts("https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyB56tD2hDxFzZTLqCFShhxfqxj8qE6Vi3I",
  authDomain: "yankees-club.firebaseapp.com",
  projectId: "yankees-club",
  storageBucket: "yankees-club.firebasestorage.app",
  messagingSenderId: "647079895639",
  appId: "1:647079895639:web:a06b7fa087e211c36c3912",
});

// Los push de la API traen "notification": el SDK los muestra solo.
firebase.messaging();
