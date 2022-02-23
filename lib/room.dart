// ignore_for_file: avoid_function_literals_in_foreach_calls, avoid_print, unnecessary_new, unnecessary_this, constant_identifier_names

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:phoenix_wings/phoenix_wings.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:room_conferrence/panchat_webrtc.dart';


const RTC_CONFIGURATION = {
  "iceServers": [
    {
      'url': "turn:113.20.119.31:3478",
      'username': "panchat",
      'credential': "panchat"
    },
    {
      "urls": "stun:stun.l.google.com:19302",
    },
  ],
  "sdpSemantics": "unified-plan"
};

const OFFER_SDP_CONSTRAINTS = {
  "mandatory": {
    // "fferToReceiveAudio": true,
    // "fferToReceiveVideo": true,
  },
  "optional": [],
};

class Room {
  late PhoenixSocket socket;
  late PhoenixChannel webRTCChannel;
  late PanchatWebRTC webRTC;

  List<Peer> peers = [];
  String? displayName;
  MediaStream? localStream;
  Function? onAddVideoElement;
  Function? onRemoveVideoElement;
  Function? onAttackStream;
  Room() {
    this.socket = PhoenixSocket(socketRTCUrl);

    this.webRTC = new PanchatWebRTC(
      RTCConfiguration(RTC_CONFIGURATION, OFFER_SDP_CONSTRAINTS),
      Callbacks(
        onSendMediaEvent: (mediaEvent) {
          this.webRTCChannel.push(
            event: "mediaEvent",
            payload: {"data": mediaEvent}
          );
        },
        onJoinSuccess: (peerId, peersInRoom) {
          this.localStream!.getTracks().forEach((track) {
            this.webRTC.addTrack(track, this.localStream!);
          });
          
          this.peers = peersInRoom.map((peerData) => Peer(id: peerData["id"], trackIdToMetadata: peerData["trackIdToMetadata"], metadata: peerData["metadata"])).toList();
          this.peers.forEach((peer) {
            this.onAddVideoElement?.call(peer.id, peer.metadata["displayName"], false);
          });
        },
        onTrackReady: (trackContext){
          print("Track ready of peer: ${trackContext.peer.id}");
          this.onAttackStream?.call(trackContext.peer.id, trackContext.stream);
        },
        onPeerJoined: (peer) {
          this.peers.add(peer);
          this.onAddVideoElement?.call(peer.id, peer.metadata["displayName"], false);
        },
        onPeerLeft: (peer) {
          this.peers.removeWhere((localPeer) => localPeer.id == peer.id);
          this.onRemoveVideoElement?.call(peer.id);
        }
      )
    );
  }

  Future<void> connect() async {
    await this.socket.connect();
    this.webRTCChannel = this.socket.channel('room:hiepleess');
  }

  Future<void> join () async {
    try {
      this.localStream = await Helper.openCamera({
        'audio': true,
        'video': {
          'mandatory': {
            'minWidth': '1280',
            'minHeight': '720',
            'minFrameRate': '60',
          },
          'optional': []
        },
      });
      await this.onAddVideoElement?.call("LOCAL_PEER_ID", "Me", true);
      this.onAttackStream?.call("LOCAL_PEER_ID", this.localStream);

      this.webRTCChannel.join()?.receive("ok", (response) async => {
        this.webRTC.join({"displayName": "Pancake Chat"})
      });
      this.webRTCChannel.on("mediaEvent", (payload, ref, joinRef) {
        this.webRTC.receiveMediaEvent(payload!["data"]);
      });
    } catch (e) {
      print("error ${e.toString()}");
    }
  }
  void leave() {
    this.webRTC.leave();
    this.webRTCChannel.leave();
    this.socket.disconnect();
  }
}

class RoomUI extends StatefulWidget {
  const RoomUI({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _RoomUIState();
  }
}

class _RoomUIState extends State<RoomUI> {
  List peersElement = [];
  Room? room;
  
  @override
  void initState() {
    super.initState();
    room = new Room();
    room!.onAddVideoElement = (id, metadata, localPeer) async {
      RTCVideoRenderer newPeerRender = new RTCVideoRenderer();
      await newPeerRender.initialize();
      final newPeer = {"id": id, "metadata": metadata, "renderer": newPeerRender};
      setState(() => peersElement.add(newPeer));
    };
    room!.onAttackStream = (id, stream) {
      final indexPeerElement = peersElement.indexWhere((element) => element["id"] == id);
      if (indexPeerElement != -1) {
        setState(() {
          (peersElement[indexPeerElement]["renderer"] as RTCVideoRenderer).srcObject = stream;
        });
      }
    };
    room!.onRemoveVideoElement = (id) {
      final indexPeerElement = peersElement.indexWhere((element) => element["id"] == id);
      print("Remove: ${peersElement[indexPeerElement]["id"]}");
      if (indexPeerElement != -1) {
        try {
          var _tempElement = peersElement[indexPeerElement]["renderer"];
          this.setState(() {
            peersElement[indexPeerElement]["renderer"] = null;
            peersElement = peersElement.where((element) => element["renderer"] != null).toList();
          });
          Future.delayed(const Duration(milliseconds: 200), () {
            _tempElement.srcObject = null;
            _tempElement.dispose();
          });
        } catch (e, trace) {
          print("$e\n$trace");
        }
      }
      
    };

    room!.connect().then((_) => room!.join());
  }

  @override
  void dispose() {
    peersElement.forEach((element) {element["renderer"].dispose();});
    peersElement.clear();
    room = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 100.0, vertical: 20.0),
        color: const Color(0xff3D3D3D),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () {
                    // collapse = !collapse;
                    // widget.screenStateCallback(collapse);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xff5E5E5E),
                      borderRadius: BorderRadius.circular(19)
                    ),
                    width: 38,
                    height: 38,
                    child: const Icon(PhosphorIcons.arrowLeft, size: 20, color: Color(0xffEDEDED)),
                  ),
                ),
                Column(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(5),
                      // child: Text(user["full_name"], style: TextStyle(fontSize: 18, color: isDark ? Color(0xffDBDBDB) : Color(0xff3D3D3D))),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () {
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xff5E5E5E) ,
                      borderRadius: BorderRadius.circular(19)
                    ),
                    width: 38,
                    height: 38,
                    // child: SvgPicture.asset('assets/icons/settings.svg')
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraint) {
                  final maxWidth = (constraint.maxWidth - 30) / 2;
                  final maxHeight = (constraint.maxHeight - 20) / ( (peersElement.length + 1) / 2);
                  return Wrap(
                    children: [
                      ...peersElement.map((peer) {
                        return Container(
                          key: Key(peer["id"]),
                          color: Colors.black,
                          width: maxWidth,
                          height: maxHeight,
                          child: Stack(
                            children: [
                              RTCVideoView(
                                peer["renderer"],
                                mirror: peer["id"] == "LOCAL_PEER_ID" ? true : false,
                                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                              ),
                              Positioned(
                                right: 30.0,
                                bottom: 10.0,
                                child: Text(peer["metadata"])
                              )
                            ],
                          ),
                        );
                      }),
                    ],
                    spacing: 30.0,
                    runSpacing: 20.0,
                  );
                }
              ),
            ),
            InkWell(
              onTap: () {
                room!.leave();
                Navigator.pop(context);
              } ,
              child: Container(child: const Center(child: Icon(PhosphorIcons.phoneDisconnectThin, color: Colors.white)), width: 55, height: 55, decoration: BoxDecoration(borderRadius: BorderRadius.circular(50), color: const Color(0xffEB5757))),
            ),
          ],
        ),
      ),
    );
  }
}