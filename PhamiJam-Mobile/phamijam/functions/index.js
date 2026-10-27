const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();

exports.onPlayCreated = onDocumentCreated(
  "users/{authorUid}/plays/{playId}",
  async (event) => {
    const { authorUid } = event.params;
    const play = event.data?.data();
    if (!play) return;

    const authorDoc = await db.collection("users").doc(authorUid).get();
    const profile = authorDoc.data()?.profile ?? {};
    if (profile.showActivityEnabled === false) return;

    const friendsSnapshot = await db
      .collection("users")
      .doc(authorUid)
      .collection("friends")
      .get();
    if (friendsSnapshot.empty) return;

    const tokensByFriend = await Promise.all(
      friendsSnapshot.docs.map((doc) =>
        db
          .collection("users")
          .doc(doc.id)
          .collection("fcmTokens")
          .get()
          .then((snap) => snap.docs.map((t) => t.id))
      )
    );
    const tokens = [...new Set(tokensByFriend.flat())];
    if (tokens.length === 0) return;

    let displayName = profile.displayNameOverride;
    if (!displayName) {
      try {
        const authRecord = await getAuth().getUser(authorUid);
        displayName = authRecord.displayName || "A friend";
      } catch (_error) {
        displayName = "A friend";
      }
    }

    const title = `${displayName} is listening`;
    const body = play.a ? `${play.t} · ${play.a}` : play.t || "a new song";

    const response = await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: {
        type: "friend_activity",
        friendUid: authorUid,
      },
    });

    const staleTokens = [];
    response.responses.forEach((result, index) => {
      if (
        !result.success &&
        result.error?.code === "messaging/registration-token-not-registered"
      ) {
        staleTokens.push(tokens[index]);
      }
    });
    if (staleTokens.length > 0) {
      await Promise.all(
        friendsSnapshot.docs.map((doc) =>
          Promise.all(
            staleTokens.map((token) =>
              db
                .collection("users")
                .doc(doc.id)
                .collection("fcmTokens")
                .doc(token)
                .delete()
                .catch(() => {})
            )
          )
        )
      );
    }
  }
);
