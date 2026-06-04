package window_german_drinking_game.com.game

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.database.DataSnapshot
import com.google.firebase.database.DatabaseError
import com.google.firebase.database.DatabaseReference
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ValueEventListener
import kotlin.random.Random

class FirebaseRoomRepository(context: Context) {
    private val appContext = context.applicationContext

    private fun database(): FirebaseDatabase {
        if (FirebaseApp.getApps(appContext).isEmpty()) {
            throw IllegalStateException(
                "Firebase is not configured. Add android/app/google-services.json from your Firebase project."
            )
        }
        val options = FirebaseOptions.fromResource(appContext)
        if (options?.databaseUrl.isNullOrBlank()) {
            throw IllegalStateException(
                "Firebase Realtime Database URL is missing. Create a Realtime Database, then re-download android/app/google-services.json."
            )
        }
        return FirebaseDatabase.getInstance()
    }

    private fun auth(): FirebaseAuth {
        if (FirebaseApp.getApps(appContext).isEmpty()) {
            throw IllegalStateException(
                "Firebase is not configured. Add android/app/google-services.json from your Firebase project."
            )
        }
        return FirebaseAuth.getInstance()
    }

    fun signInAnonymously(
        onSuccess: (String) -> Unit,
        onError: (String) -> Unit,
    ) {
        try {
            val currentUser = auth().currentUser
            if (currentUser != null) {
                onSuccess(currentUser.uid)
                return
            }
            auth().signInAnonymously()
                .addOnSuccessListener { result ->
                    val uid = result.user?.uid
                    if (uid == null) {
                        onError("Anonymous sign-in returned no user.")
                    } else {
                        onSuccess(uid)
                    }
                }
                .addOnFailureListener { onError(it.message ?: "Anonymous sign-in failed.") }
        } catch (error: IllegalStateException) {
            onError(error.message ?: "Firebase is not configured.")
        }
    }

    fun createRoom(
        initialState: SerializableGameState,
        onSuccess: (String) -> Unit,
        onError: (String) -> Unit,
    ) {
        val roomCode = generateRoomCode()
        val stateRef = roomStateRef(roomCode)
        stateRef.setValue(initialState.copy(version = 1, updatedAt = System.currentTimeMillis()))
            .addOnSuccessListener { onSuccess(roomCode) }
            .addOnFailureListener { onError(it.message ?: "Could not create room.") }
    }

    fun loadRoomOnce(
        roomCode: String,
        onSuccess: (SerializableGameState) -> Unit,
        onMissing: () -> Unit,
        onError: (String) -> Unit,
    ) {
        roomStateRef(roomCode).get()
            .addOnSuccessListener { snapshot ->
                val state = snapshot.getValue(SerializableGameState::class.java)
                if (state == null) {
                    onMissing()
                } else {
                    onSuccess(state)
                }
            }
            .addOnFailureListener { onError(it.message ?: "Could not load room.") }
    }

    fun observeRoom(
        roomCode: String,
        onState: (SerializableGameState) -> Unit,
        onError: (String) -> Unit,
    ): () -> Unit {
        val ref = roomStateRef(roomCode)
        val listener = object : ValueEventListener {
            override fun onDataChange(snapshot: DataSnapshot) {
                snapshot.getValue(SerializableGameState::class.java)?.let(onState)
            }

            override fun onCancelled(error: DatabaseError) {
                onError(error.message)
            }
        }
        ref.addValueEventListener(listener)
        return { ref.removeEventListener(listener) }
    }

    fun writeState(
        roomCode: String,
        state: SerializableGameState,
        onError: (String) -> Unit,
    ) {
        roomStateRef(roomCode).setValue(state.copy(updatedAt = System.currentTimeMillis()))
            .addOnFailureListener { onError(it.message ?: "Could not update room.") }
    }

    private fun roomStateRef(roomCode: String): DatabaseReference {
        return database().reference
            .child("rooms")
            .child(roomCode.trim().uppercase())
            .child("state")
    }

    private fun generateRoomCode(): String {
        val alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return (1..6).map { alphabet[Random.nextInt(alphabet.length)] }.joinToString("")
    }
}
