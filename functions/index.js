const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
const http2 = require('http2');
const crypto = require('crypto');
admin.initializeApp();

/**
 * Helper to sign an APNs JWT token using Apple ES256 private key.
 */
function createApnsJwt(keyId, teamId, privateKeyPem) {
    const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: keyId })).toString('base64url');
    const now = Math.floor(Date.now() / 1000);
    const claims = Buffer.from(JSON.stringify({ iss: teamId, iat: now })).toString('base64url');
    const signInput = `${header}.${claims}`;

    const signer = crypto.createSign('SHA256');
    signer.update(signInput);
    signer.end();
    const signature = signer.sign(privateKeyPem, 'base64url');

    return `${signInput}.${signature}`;
}

/**
 * Sends a native Apple PushKit VoIP notification over HTTP/2.
 * Requires APNS_KEY_ID, APNS_TEAM_ID, APNS_AUTH_KEY, and optional APNS_BUNDLE_ID in process.env.
 */
async function sendApnsVoipPush({ voipToken, roomId, callerName, callerId, callerPic, isVideoCall }) {
    const keyId = process.env.APNS_KEY_ID;
    const teamId = process.env.APNS_TEAM_ID;
    const authKey = process.env.APNS_AUTH_KEY; // PEM string or base64 encoded PEM
    const bundleId = process.env.APNS_BUNDLE_ID || 'com.example.cuqter';
    const isProduction = process.env.APNS_PRODUCTION === 'true';

    if (!keyId || !teamId || !authKey) {
        console.log('APNs credentials not configured (APNS_KEY_ID/APNS_TEAM_ID/APNS_AUTH_KEY). PushKit push skipped; relying on high-priority FCM.');
        return false;
    }

    let pemKey = authKey;
    if (!pemKey.includes('-----BEGIN PRIVATE KEY-----')) {
        pemKey = Buffer.from(authKey, 'base64').toString('utf8');
    }

    const host = isProduction ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com';
    const token = createApnsJwt(keyId, teamId, pemKey);

    const payload = JSON.stringify({
        aps: {
            alert: `Incoming ${isVideoCall ? 'video' : 'voice'} call from ${callerName}`,
        },
        id: roomId,
        nameCaller: callerName,
        callerId: callerId,
        callerPic: callerPic || '',
        handle: isVideoCall ? 'Incoming Video Call' : 'Incoming Voice Call',
        isVideo: isVideoCall,
        extra: {
            roomId: roomId,
            callerId: callerId,
            callerName: callerName,
            callerPic: callerPic || '',
            isVideoCall: isVideoCall,
        },
    });

    return new Promise((resolve) => {
        const client = http2.connect(host);
        client.on('error', (err) => {
            console.error('APNs HTTP/2 connection error:', err);
            resolve(false);
        });

        const req = client.request({
            ':method': 'POST',
            ':path': `/3/device/${voipToken}`,
            'authorization': `bearer ${token}`,
            'apns-topic': `${bundleId}.voip`,
            'apns-push-type': 'voip',
            'apns-priority': '10',
            'apns-expiration': '0',
            'content-type': 'application/json',
            'content-length': Buffer.byteLength(payload),
        });

        req.setEncoding('utf8');
        let responseData = '';

        req.on('response', (headers) => {
            const status = headers[':status'];
            if (status === 200) {
                console.log('APNs PushKit VoIP notification delivered successfully.');
            } else {
                console.warn(`APNs PushKit returned status: ${status}`);
            }
        });

        req.on('data', (chunk) => {
            responseData += chunk;
        });

        req.on('end', () => {
            client.close();
            resolve(true);
        });

        req.on('error', (err) => {
            console.error('APNs request error:', err);
            client.close();
            resolve(false);
        });

        req.write(payload);
        req.end();
    });
}

/**
 * Triggered on new chat messages in Firestore.
 * Sends high-priority push with BOTH notification and data blocks so the OS displays banners
 * immediately when the app is backgrounded or terminated.
 */
exports.sendChatNotification = functions.region('asia-south1').firestore
    .document('chats/{chatId}/messages/{messageId}')
    .onCreate(async (snapshot, context) => {
        const messageData = snapshot.data();
        if (!messageData) {
            console.log('No message data found.');
            return null;
        }

        const receiverId = messageData.receiverId;
        const senderId = messageData.senderId;
        const rawText = messageData.text || '';
        const messageType = messageData.type || 'text';

        // Produce a user-friendly notification body based on message type
        let notificationBody;
        switch (messageType) {
            case 'video_call': notificationBody = 'Incoming Video Call'; break;
            case 'voice_call': notificationBody = 'Incoming Voice Call'; break;
            case 'image':    notificationBody = '📷 Photo'; break;
            case 'video':    notificationBody = '🎥 Video'; break;
            case 'audio':    notificationBody = '🎵 Audio'; break;
            case 'document': notificationBody = '📄 Document'; break;
            case 'location': notificationBody = '📍 Shared a location'; break;
            default:
                notificationBody = rawText.split('|')[0] || 'Sent a message';
        }

        // 1. Fetch recipient's FCM token
        const receiverDoc = await admin.firestore().collection('users').doc(receiverId).get();
        if (!receiverDoc.exists) {
            console.log('Receiver document does not exist.');
            return null;
        }
        
        const receiverData = receiverDoc.data();
        const fcmToken = receiverData.fcmToken;

        if (!fcmToken) {
            console.log('No FCM token found for user:', receiverId);
            return null;
        }

        // 2. Fetch sender's name and profile picture
        const senderDoc = await admin.firestore().collection('users').doc(senderId).get();
        let senderName = 'New Message';
        let senderProfilePic = '';
        if (senderDoc.exists) {
            const senderData = senderDoc.data();
            senderName = senderData.name || senderData.username || 'New Message';
            senderProfilePic = senderData.profilepic || '';
        }

        // 3. Construct Notification Payload with BOTH notification and data blocks
        // The notification block ensures the OS displays heads-up banners immediately when the
        // app is backgrounded or terminated without requiring the user to open the app first.
        const message = {
            notification: {
                title: senderName,
                body: notificationBody,
            },
            data: {
                title: senderName,
                body: notificationBody,
                chatId: context.params.chatId,
                senderId: senderId,
                receiverId: receiverId,
                senderProfilePic: senderProfilePic,
                type: messageType,
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
            },
            android: {
                priority: 'high',
                notification: {
                    channelId: 'chats_messages_channel',
                    priority: 'high',
                    defaultSound: true,
                    defaultVibrateTimings: true,
                    clickAction: 'FLUTTER_NOTIFICATION_CLICK',
                    tag: context.params.chatId,
                },
            },
            apns: {
                headers: {
                    'apns-priority': '10',
                },
                payload: {
                    aps: {
                        alert: {
                            title: senderName,
                            body: notificationBody,
                        },
                        sound: 'default',
                        badge: 1,
                        contentAvailable: true,
                        category: 'chats_messages_category',
                        threadId: context.params.chatId,
                    },
                },
            },
            token: fcmToken,
        };

        // 4. Send Message via FCM
        try {
            const response = await admin.messaging().send(message);
            console.log('Chat notification sent successfully:', response);
        } catch (error) {
            console.error('Error sending chat notification:', error);
        }
        return null;
    });

/**
 * Triggered on new friend requests in Firestore.
 */
exports.sendFriendRequestNotification = functions.region('asia-south1').firestore
    .document('friend_requests/{requestId}')
    .onCreate(async (snapshot, context) => {
        const requestData = snapshot.data();
        if (!requestData) {
            console.log('No request data found.');
            return null;
        }

        const receiverId = requestData.receiverId;
        const senderId = requestData.senderId;
        const senderName = requestData.senderName || 'Someone';
        
        if (requestData.status !== 'pending') {
            return null;
        }

        const receiverDoc = await admin.firestore().collection('users').doc(receiverId).get();
        if (!receiverDoc.exists) {
            console.log('Receiver document does not exist.');
            return null;
        }
        
        const receiverData = receiverDoc.data();
        const fcmToken = receiverData.fcmToken;

        if (!fcmToken) {
            console.log('No FCM token found for user:', receiverId);
            return null;
        }

        const message = {
            notification: {
                title: 'New Friend Request',
                body: `${senderName} sent you a friend request`,
            },
            data: {
                title: 'New Friend Request',
                body: `${senderName} sent you a friend request`,
                type: 'friend_request',
                senderId: senderId,
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
            },
            android: {
                priority: 'high',
                notification: {
                    channelId: 'friend_requests_channel',
                    priority: 'high',
                    defaultSound: true,
                    defaultVibrateTimings: true,
                    clickAction: 'FLUTTER_NOTIFICATION_CLICK',
                },
            },
            apns: {
                headers: {
                    'apns-priority': '10',
                },
                payload: {
                    aps: {
                        alert: {
                            title: 'New Friend Request',
                            body: `${senderName} sent you a friend request`,
                        },
                        sound: 'default',
                        badge: 1,
                        contentAvailable: true,
                        category: 'friend_requests_category',
                    },
                },
            },
            token: fcmToken,
        };

        try {
            const response = await admin.messaging().send(message);
            console.log('Friend request notification sent successfully:', response);
        } catch (error) {
            console.error('Error sending friend request notification:', error);
        }
        return null;
    });

/**
 * Triggered on incoming calls in Realtime Database.
 * Dispatches high-priority data payloads with TTL for Android Full-Screen Intent
 * and native PushKit VoIP pushes for iOS CallKit.
 */
exports.sendCallInviteNotification = functions.region('asia-south1').database
    .ref('incoming_calls/{receiverId}')
    .onCreate(async (snapshot, context) => {
        const callData = snapshot.val();
        if (!callData) return null;

        const receiverId = context.params.receiverId;
        const callerId = callData.callerId;
        const callerName = callData.callerName || 'Someone';
        const callerPic = callData.callerPic || '';
        const roomId = callData.roomId;
        const isVideoCall = callData.isVideo || false;

        // Fetch recipient's tokens from Firestore
        const receiverDoc = await admin.firestore().collection('users').doc(receiverId).get();
        if (!receiverDoc.exists) return null;
        
        const receiverData = receiverDoc.data();
        const fcmToken = receiverData.fcmToken;
        const voipToken = receiverData.voipToken;

        // 1. Dispatch Apple PushKit VoIP Push for iOS (triggers native CallKit when terminated)
        if (voipToken) {
            try {
                await sendApnsVoipPush({
                    voipToken: voipToken,
                    roomId: roomId,
                    callerName: callerName,
                    callerId: callerId,
                    callerPic: callerPic,
                    isVideoCall: isVideoCall,
                });
            } catch (voipErr) {
                console.error('Error dispatching APNs VoIP push:', voipErr);
            }
        }

        // 2. Dispatch high-priority FCM data payload for Android Full-Screen Intent (and fallback for iOS)
        if (fcmToken) {
            const message = {
                data: {
                    type: 'call_invite',
                    callerName: callerName,
                    callerId: callerId,
                    callerPic: callerPic,
                    roomId: roomId,
                    isVideoCall: isVideoCall ? 'true' : 'false',
                    click_action: 'FLUTTER_NOTIFICATION_CLICK',
                },
                android: {
                    priority: 'high',
                    ttl: 35 * 1000, // 35 seconds TTL for call invites
                },
                apns: {
                    headers: {
                        'apns-priority': '10',
                        'apns-push-type': 'background',
                    },
                    payload: {
                        aps: {
                            contentAvailable: true,
                        },
                    },
                },
                token: fcmToken,
            };

            try {
                const response = await admin.messaging().send(message);
                console.log('Call invite FCM sent successfully:', response);
            } catch (error) {
                console.error('Error sending call invite FCM:', error);
            }
        }
        return null;
    });

/**
 * Triggered on call cancellation in Realtime Database.
 */
exports.cancelCallInviteNotification = functions.region('asia-south1').database
    .ref('incoming_calls/{receiverId}')
    .onDelete(async (snapshot, context) => {
        const callData = snapshot.val();
        if (!callData) return null;

        const receiverId = context.params.receiverId;
        const roomId = callData.roomId;

        const receiverDoc = await admin.firestore().collection('users').doc(receiverId).get();
        if (!receiverDoc.exists) return null;
        
        const receiverData = receiverDoc.data();
        const fcmToken = receiverData.fcmToken;
        if (!fcmToken) return null;

        const message = {
            data: {
                type: 'call_cancel',
                roomId: roomId,
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
            },
            android: {
                priority: 'high',
                ttl: 10 * 1000,
            },
            apns: {
                headers: {
                    'apns-priority': '10',
                    'apns-push-type': 'background',
                },
                payload: {
                    aps: {
                        contentAvailable: true,
                    },
                },
            },
            token: fcmToken,
        };

        try {
            await admin.messaging().send(message);
            console.log('Call cancel FCM sent successfully');
        } catch (error) {
            console.error('Error sending call cancel notification:', error);
        }
        return null;
    });
