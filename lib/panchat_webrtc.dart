// ignore_for_file: unnecessary_this, avoid_function_literals_in_foreach_calls, avoid_print, curly_braces_in_flow_control_structures, unnecessary_new, prefer_collection_literals, prefer_generic_function_type_aliases

import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

class RTCConfiguration {
  late Map<String, dynamic> configuration;
  late Map<String, dynamic> offerSdpConstraints;
  RTCConfiguration(this.configuration, this.offerSdpConstraints);
}

class Callbacks {
  SendMediaEventCallback? onSendMediaEvent;
  JoinSuccessCallback? onJoinSuccess;
  JoinErrorCallback? onJoinError;
  PeerCallback? onPeerJoined;
  PeerCallback? onPeerLeft;
  PeerCallback? onPeerUpdated;
  TrackCallback? onTrackReady;
  TrackCallback? onTrackAdded;
  TrackCallback? onTrackRemoved;
  TrackCallback? onTrackUpdated;
  ConnectionCallback? onConnectionError;
  Callbacks(
      {this.onSendMediaEvent,
      this.onJoinSuccess,
      this.onTrackAdded,
      this.onPeerJoined,
      this.onTrackReady,
      this.onPeerLeft});
}

class MediaEvent {
  String type;
  Map<String, dynamic> data;
  MediaEvent({required this.type, required this.data});
  @override
  String toString() {
    return "type: $type, data: ${data.toString()}";
  }
}

class Peer {
  String id;
  dynamic metadata;
  Map<String, dynamic> trackIdToMetadata;
  Peer({required this.id, this.metadata, required this.trackIdToMetadata});

  static Peer from(Map data) {
    return Peer(
        id: data["id"],
        trackIdToMetadata: data["trackIdToMetadata"],
        metadata: data["metadata"]);
  }
}

class TrackContext {
  MediaStreamTrack? track;
  MediaStream? stream;
  Peer peer;
  String trackId;
  dynamic metadata;

  TrackContext(
      {this.track,
      this.stream,
      required this.peer,
      required this.trackId,
      this.metadata});
}

const apiRTCUrl = 'http://203.205.10.141:4000/api';
const socketRTCUrl = 'ws://203.205.10.141:4000/socket/websocket';
// const apiRTCUrl = 'http://192.168.3.6:4000/api';
// const socketRTCUrl = 'ws://192.168.3.6:4000/socket/websocket';

typedef void SendMediaEventCallback(event);
typedef void StreamCallback(stream);
typedef JoinSuccessCallback = void Function(String peerId, List peersInRoom);
typedef JoinErrorCallback = void Function(dynamic metadata);
typedef PeerCallback = void Function(Peer peer);
typedef TrackCallback = void Function(TrackContext trackContext);
typedef ConnectionCallback = void Function(String message);

class PanchatWebRTC {
  List<Set> localTrackWithStream = [];
  RTCConfiguration rtcConfig;
  Map<String, Peer> idToPeer = new Map();
  Peer localPeer = Peer(id: "", metadata: {}, trackIdToMetadata: new Map());
  Map<String, TrackContext> localTrackIdToTrack = new Map();
  Map<String, String> midToTrackId = new Map();
  Map<String, TrackContext> trackIdToTrack = new Map();

  RTCPeerConnection? connection;
  Callbacks callbacks;
  PanchatWebRTC(this.rtcConfig, this.callbacks);

  Future<void> receiveMediaEvent(event) async {
    MediaEvent mediaEvent = deserializeMediaEvent(event);
    // print("Receive: ${mediaEvent.type} ${mediaEvent.data}");
    switch (mediaEvent.type) {
      case "peerAccepted":
        this.localPeer.id = mediaEvent.data["id"];
        this
            .callbacks
            .onJoinSuccess
            ?.call(mediaEvent.data["id"], mediaEvent.data["peersInRoom"]);

        final peers = mediaEvent.data["peersInRoom"]
            .map((e) => Peer.from(e))
            .toList() as List;
        peers.forEach((peer) {
          this.addPeer(peer);
        });
        break;
      case "peerDenied":
        break;
      default:
        if (this.localPeer.id != "") this.handleMediaEvent(mediaEvent);
    }
  }

  void handleMediaEvent(MediaEvent event) {
    Peer? peer;
    switch (event.type) {
      case "offerData":
        print("\nOFFER DATA");
        final offerData =
            new Map.from(event.data["tracksTypes"]).cast<String, int>();
        this.onOfferData(offerData);
        break;
      case "sdpAnswer":
        // print(event.data);
        this.midToTrackId = new Map.from(event.data["midToTrackId"]);
        this.onAnswer(event.data);
        break;
      case "candidate":
        this.onRemoteCandidate(event.data);
        break;
      case "peerJoined":
        peer = new Peer(
          id: event.data["peer"]["id"] ?? "",
          trackIdToMetadata: event.data["peer"]["trackIdToMetadata"] ?? {},
          metadata: event.data["peer"]["metadata"] ?? {});
        if (peer.id == this.getPeerId()) return;
        this.addPeer(peer);
        this.callbacks.onPeerJoined?.call(peer);
        // print("New peer joined ${peer.metadata["displayName"]}");
        break;
      case "peerLeft":
        print("Me: ${this.getPeerId()}, left: ${this.idToPeer[event.data["peerId"]]?.id}");
        peer = this.idToPeer[event.data["peerId"]];
        if (peer == null || peer.id == this.getPeerId()) return;
        peer.trackIdToMetadata.keys.forEach((trackId) {
          this.callbacks.onTrackRemoved?.call(this.trackIdToTrack[trackId]!);
        });
        this.erasePeer(peer);
        this.callbacks.onPeerLeft?.call(peer);
        break;
      case "peerUpdated":
        if (this.getPeerId() == event.data["peerId"]) return;
        peer = this.idToPeer[event.data["peerId"]]!;
        peer.metadata = event.data["metadata"];
        this.addPeer(peer);
        this.callbacks.onPeerUpdated?.call(peer);
        break;
      case "tracksAdded":
        final data = event.data;
        if (this.getPeerId() == data["peerId"]) return;
        peer = this.idToPeer[data["peerId"]];
        final oldTrackIdToMetadata = peer?.trackIdToMetadata;
        peer?.trackIdToMetadata = {
          ...peer.trackIdToMetadata,
          ...data["trackIdToMetadata"]
        };
        this.idToPeer[peer!.id] = peer;
        peer.trackIdToMetadata.entries.forEach((element) {
          final trackId = element.key;
          final metadata = element.value;
          if (!oldTrackIdToMetadata!.containsKey(trackId)) {
            final ctx =
                TrackContext(peer: peer!, trackId: trackId, metadata: metadata);
            this.trackIdToTrack[trackId] = ctx;
            this.callbacks.onTrackAdded?.call(ctx);
          }
        });
        // print("Track Added");
        break;
      case "trackUpdated":
        if (this.getPeerId() == event.data["peerId"]) return;
        peer = this.idToPeer[event.data["peerId"]];
        if (peer == null)
          throw "Peer with id ${event.data["peerId"]} doesn't not exit";
        final trackId = event.data["trackId"];
        final trackMetadata = event.data["metadata"];
        peer.trackIdToMetadata[trackId] = trackMetadata;
        final trackContext = this.trackIdToTrack[trackId];
        trackContext!.metadata = trackMetadata;
        this.callbacks.onTrackUpdated?.call(trackContext);
        break;
      case "tracksRemoved":
        final data = event.data;
        final peerId = data["peerId"];
        if (this.getPeerId() == peerId) return;
        final trackIds = List.from(data["trackIds"]);
        trackIds.forEach((trackId) {
          final trackContext = this.trackIdToTrack[trackId]!;
          this.callbacks.onTrackRemoved?.call(trackContext);
          this.eraseTrack(trackId, peerId);
        });
        break;
      case "custom":
        MediaEvent customEvent =
            MediaEvent(type: event.data["type"], data: event.data["data"]);
        this.handleMediaEvent(customEvent);
        break;
      // case "error":
      //   this.callbacks.onConnectionError?.call(event.data["message"]);
      //   this.leave();
      // break;
    }
  }

  void join(selfMetadata) {
    try {
      final mediaEvent =
          MediaEvent(type: "join", data: {"metadata": selfMetadata});
      this.sendMediaEvent(mediaEvent);
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> onOfferData(Map<String, int> offerData) async {
    if (this.connection == null) {
      this.connection = await createPeerConnection(
          this.rtcConfig.configuration, this.rtcConfig.offerSdpConstraints);
      this.connection!.onIceCandidate = this.onLocalCandidate;
      this.connection!.onIceGatheringState = (state) {
        print(state.toString());
      };
      this.connection!.onSignalingState = (state) {
        print(state.toString());
      };
      this.connection!.onConnectionState = (state) async {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          (await this.connection!.getStats()).forEach((stat) {
          // if (stat.type == "localcandidate" || stat.type == "remotecandidate")
          //   print("${stat.type} ${stat.values}");
        });
        }
        
        // print("asdasdasdsd${state.toString()}");
      };
      this.connection!.onIceConnectionState = (state) {
        print(state.toString());
        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          MediaEvent event = generateCustomEvent(MediaEvent(type: "renegotiateTracks", data: {}));
          print("Renegotiate track ${event.toString()}");
          this.sendMediaEvent(event);
          print("Re on Offer data");
          // this.onOfferData({});
        }
      };

      this.localTrackWithStream.forEach((e) async {
        final track = e.first as MediaStreamTrack;
        final stream = e.last;
        await this
            .connection!
            .addTrack(track, stream)
            .then((value) => print("ADD TRACK ${value.track?.kind} COMPLETE"));
      });

      // await this
      //     .connection!
      //     .setAllTransceiverToOnlyDirection(TransceiverDirection.SendOnly);

      // (await this.connection!.getTransceivers()).forEach((element) async {
      //   await element.setDirection(TransceiverDirection.SendOnly);
      // });
      // (await this.connection!.getTransceivers()).forEach((element) async {
      //   // print(await element.getCurrentDirection());
      //   print(element.transceiverId);
      // });
    } else {
      this.connection!.restartIce();
    }

    await this.createAndSendOffer(offerData);
  }

  Future<void> createAndSendOffer(offerData) async {
    if (this.connection == null) return;
    try {
      RTCSessionDescription description =
          await this.connection!.createOffer({});
      // print("beforre: ${description.toMap()}\n\n");
      await this
          .connection!
          .setLocalDescription(description)
          .then((_) => print("Set LocalDescription complete"))
          .onError((error, stackTrace) =>
              print("ERROR SET LOCALDESCRIPTION$error $stackTrace"));

      await Future.forEach<RTCRtpTransceiver>((await this.connection!.getTransceivers()), (transceiver) async {
        if (await transceiver.getCurrentDirection() == TransceiverDirection.SendRecv || await transceiver.getDirection() == TransceiverDirection.SendRecv) {
          await transceiver.setDirection(TransceiverDirection.SendOnly);
        }
      });
  
      await this.addTransceiversIfNeeded(offerData);
      description = await this.connection!.createOffer({});
      // description.sdp = description.sdp!.replaceAll('setup:actpass','setup:active');
      await this.connection!.setLocalDescription(description);

      final mediaEvent = MediaEvent(type: "sdpOffer", data: {
        "sdpOffer": description.toMap(),
        "trackIdToTrackMetadata": getTrackIdToMetadata(),
        "midToTrackId": await this.getMidToTrackId()
      });
      // print(description.toMap());

      this.sendMediaEvent(generateCustomEvent(mediaEvent));
    } catch (e, stack) {
      print(e.toString() + stack.toString());
    }
  }

  Future<void> onAnswer(answer) async {
    this.connection!.onTrack = this.onTrack;
    try {
      RTCSessionDescription description =
          new RTCSessionDescription(answer["sdp"], answer["type"]);
          // print(description.toMap());
      await this
          .connection!
          .setRemoteDescription(description)
          .then((value) => print("Set remotedescription complete!!!!!"))
          .onError((error, stackTrace) =>
              print("ERROR Set REMOTEDESCRIPTION $error $stackTrace"));
    } catch (e, track) {
      print(e.toString() + "\n" + track.toString());
    }
  }

  Future<void> onTrack(RTCTrackEvent event) async {
    final streams = event.streams;
    final mid = event.transceiver?.mid;
    final trackId = this.midToTrackId[mid];
    final peer = this
        .idToPeer
        .values
        .firstWhere((peer) => peer.trackIdToMetadata.keys.contains(trackId));
    final metadata = peer.trackIdToMetadata[trackId];
    final trackContext = TrackContext(
        peer: peer,
        trackId: trackId!,
        stream: streams[0],
        track: event.track,
        metadata: metadata);

    this.trackIdToTrack[trackId] = trackContext;
    // print("New track ready ${event.track.kind}");
    this.callbacks.onTrackReady?.call(trackContext);
  }

  void onLocalCandidate(RTCIceCandidate? iceCandidate) {
    if (iceCandidate != null) {
      final event = MediaEvent(type: 'candidate', data: {
        'candidate': iceCandidate.candidate.toString(),
        'sdpMLineIndex': iceCandidate.sdpMLineIndex,
        'sdpMid': iceCandidate.sdpMid
      });
      // print("local candidate ${iceCandidate.toMap().toString()}");
      this.sendMediaEvent(generateCustomEvent(event));
    }
  }

  void onRemoteCandidate(candidate) {
    try {
      // print("remote candidate $candidate");
      RTCIceCandidate iceCandidate = RTCIceCandidate(
          candidate["candidate"],
          candidate["sdpMLineIndex"].toString(),
          candidate["sdpMLineIndex"]);
      if (this.connection == null) return;
      this
          .connection!
          .addCandidate(iceCandidate)
          .onError((error, stackTrace) =>
              print("ERROR SET ICECANDIDATE $error $stackTrace"));
    } catch (e, trace) {
      print(e.toString() + "\n" + trace.toString());
    }
  }

  String addTrack(MediaStreamTrack track, MediaStream stream) {
    if (this.getPeerId() == "")
      throw "Cannot add tracks before being accepted by the server";

    final trackId = this.getTrackId(const Uuid().v4());
    this.localTrackWithStream.add({track, stream});
    this.localPeer.trackIdToMetadata[trackId] = {};
    this.localTrackIdToTrack[trackId] = new TrackContext(
        track: track,
        stream: stream,
        peer: this.localPeer,
        trackId: trackId,
        metadata: {});
    // print("Add track ${track.kind} to local complete");

    // if (this.connection != null) {
    //   this.connection!.addTrack(track, stream);

    //   this.connection!.getTransceivers().then((trans) => trans.forEach((tran) => {tran.setDirection(tran.currentDirection == TransceiverDirection.SendRecv ? TransceiverDirection.SendOnly : tran.currentDirection!)}));
    // }
    MediaEvent event =
        generateCustomEvent(MediaEvent(type: "renegotiateTracks", data: {}));
    Future.delayed(const Duration(milliseconds: 200), () => this.sendMediaEvent(event));

    return trackId;
  }

  Future<void> addTransceiversIfNeeded(Map<String, int> serverTracks) async {
    // print(serverTracks);
    final tranceivers = (await this.connection!.getTransceivers());
    List recvTranceivers = [];
    await Future.forEach<RTCRtpTransceiver>(tranceivers, (tranceiver) async {
      // print("direction: ${(await tranceiver.getDirection())} currentDiretion: ${(await tranceiver.getCurrentDirection())}");
      if ((await tranceiver.getDirection()) == TransceiverDirection.RecvOnly){
        // print("111111111");
        recvTranceivers.add(tranceiver);
      }
    });

    List<RTCRtpMediaType> toAdd = [];
    
    List<RTCRtpMediaType> getNeededTransceiversTypes(type) {
      var typeNumber = serverTracks[type];
      typeNumber = typeNumber ?? 0;
      if (typeNumber == 0) {
        return [];
      }
      final typeTransceiversNumber = recvTranceivers
          .where((element) => element.receiver.track?.kind == type)
          .length;
      late RTCRtpMediaType mediaType;
      // print(typeNumber);
      // print(typeTransceiversNumber);
      if (type == "audio")
        mediaType = RTCRtpMediaType.RTCRtpMediaTypeAudio;
      else if (type == "video")
        mediaType = RTCRtpMediaType.RTCRtpMediaTypeVideo;
      return List.filled(typeNumber - typeTransceiversNumber, mediaType);
    }

    final audio = getNeededTransceiversTypes('video');
    final video = getNeededTransceiversTypes('audio');
    toAdd = toAdd + audio + video;
    for (var kind in toAdd) {
      this.connection?.addTransceiver(
          kind: kind,
          init:
              RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));
    }
  }

  void addPeer(Peer peer) {
    this.idToPeer[peer.id] = peer;
  }

  void erasePeer(Peer peer) {
    final trackIds = List.from(peer.trackIdToMetadata.keys);
    trackIds.forEach((trackId){
      this.trackIdToTrack.remove(trackId);
      this.midToTrackId.remove(trackId);
    });
    // this.midToTrackId.entries.forEach((element) {
    //   final mid = element.key;
    //   final trackId = element.value;
    //   if (trackIds.contains(trackId)) this.midToTrackId.remove(mid);
    // });
    this.idToPeer.remove(peer.id);
  }

  void eraseTrack(trackId, peerId) {
    this.trackIdToTrack.remove(trackId);
    final midToTrackId = this.midToTrackId.entries;
    final midTrackIdEntry =
        midToTrackId.firstWhere((element) => trackId == element.value);
    this.midToTrackId.remove(midTrackIdEntry.key);
    this.idToPeer[peerId]!.trackIdToMetadata.remove(trackId);
  }

  getMidToTrackId() async {
    final localTrackMidToTrackId = {};

    if (this.connection == null) return;
    (await this.connection!.getTransceivers()).forEach((transceiver) {
      final localTrackId = transceiver.sender.track?.id;
      final mid = transceiver.mid;
      final trackIds = this.localPeer.trackIdToMetadata.keys;
      final tracks =
          List.from(trackIds).map((track) => this.localTrackIdToTrack[track]);

      if (localTrackId != null && mid != "") {
        final trackContext = tracks.firstWhere(
            (trackContext) => trackContext!.track!.id == localTrackId);
        localTrackMidToTrackId[mid] = trackContext!.trackId;
      }
    });
    return localTrackMidToTrackId;
  }

  getTrackIdToMetadata() {
    final trackIdToMetadata = {};
    List.from(this.localPeer.trackIdToMetadata.entries).forEach((element) {
      trackIdToMetadata[element.key] = element.value;
    });
    return trackIdToMetadata;
  }

  void leave() {
    MediaEvent event = MediaEvent(type: "leave", data: {});
    this.sendMediaEvent(event);
    this.cleanUp();
  }

  void cleanUp() {
    this.connection?.onIceCandidate = null;
    this.connection?.onTrack = null;
    this.connection?.onIceConnectionState = null;
    this.connection?.onConnectionState = null;
    this.connection?.onSignalingState = null;

    this.localTrackWithStream.forEach((e) => e.first.stop());
    this.localTrackWithStream.clear();
    this.connection?.dispose();
    this.connection = null;
  }

  void sendMediaEvent(MediaEvent event) {
    // print("Send: ${event.type} ${event.data}");
    String jsonEvent = serializeMediaEvent(event);
    this.callbacks.onSendMediaEvent!(jsonEvent);
  }

  String serializeMediaEvent(MediaEvent event) {
    String jsonEvent = json.encode({"type": event.type, "data": event.data});
    return jsonEvent;
  }

  MediaEvent deserializeMediaEvent(event) {
    final jsonEvent = json.decode(event);
    return MediaEvent(type: jsonEvent['type'], data: jsonEvent['data']);
  }

  MediaEvent generateCustomEvent(rawEvent) {
    return MediaEvent(
        type: "custom", data: {"data": rawEvent.data, "type": rawEvent.type});
  }

  String getTrackId(String uuid) {
    return "${this.getPeerId()}:$uuid";
  }

  String getPeerId() => this.localPeer.id;
}
