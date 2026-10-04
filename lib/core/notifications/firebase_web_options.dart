import 'package:firebase_core/firebase_core.dart';

/// App web del proyecto Firebase "yankees-club". Estos datos son públicos
/// (van en el código que descarga el navegador); la clave que permite enviar
/// push está solo en la API.
const firebaseWebOptions = FirebaseOptions(
  apiKey: 'AIzaSyB56tD2hDxFzZTLqCFShhxfqxj8qE6Vi3I',
  authDomain: 'yankees-club.firebaseapp.com',
  projectId: 'yankees-club',
  storageBucket: 'yankees-club.firebasestorage.app',
  messagingSenderId: '647079895639',
  appId: '1:647079895639:web:a06b7fa087e211c36c3912',
);
