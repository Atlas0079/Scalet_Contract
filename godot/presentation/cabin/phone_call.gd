extends RefCounted
## In-game telephone session contract. A game backend acknowledges connection/end.
signal changed
signal outgoing_requested(session_id: int, number: String)
signal answer_requested(session_id: int)
signal ended(session_id: int, reason: String)

var phase := "idle"
var number := ""
var peer := ""
var status := "待机"
var session_id := 0
var serial := 0
var elapsed := 0.0

func digit(value: String) -> bool:
 if phase != "idle" or value.length()!=1 or value not in "0123456789*#" or number.length()>=16: return false
 number += value
 status = "输入号码"
 changed.emit()
 return true

func clear():
 if phase != "idle": return
 number = number.left(maxi(number.length()-1,0))
 status = "待机" if number.is_empty() else "输入号码"
 changed.emit()

func dial() -> int:
 if phase != "idle": return 0
 if number.is_empty():
  status = "请输入号码"
  changed.emit()
  return 0
 serial += 1; session_id = serial
 peer = number; elapsed = 0.0; phase = "outgoing"; status = "呼叫中"
 changed.emit()
 outgoing_requested.emit(session_id,peer)
 return session_id

func receive_call(caller: String) -> int:
 if phase != "idle" or caller.is_empty(): return 0
 serial += 1; session_id = serial
 peer = caller; elapsed = 0.0; phase = "ringing"; status = "来电"
 changed.emit()
 return session_id

func answer() -> bool:
 if phase != "ringing": return false
 phase = "answering"; status = "接通中"
 changed.emit()
 answer_requested.emit(session_id)
 return true

func connect_call(id: int) -> bool:
 if id!=session_id or phase not in ["outgoing","answering"]: return false
 phase = "connected"; elapsed = 0.0; status = "通话中"
 changed.emit()
 return true

func hang_up(reason := "已挂断") -> bool:
 if phase == "idle": return false
 var id := session_id
 phase = "idle"; status = reason; peer = ""; elapsed = 0.0
 changed.emit()
 ended.emit(id,reason)
 return true

func remote_end(id: int, reason := "对方挂断") -> bool:
 if id!=session_id or phase == "idle": return false
 return hang_up(reason)

func advance(delta: float):
 if phase != "connected": return
 var before := int(elapsed)
 elapsed += maxf(delta,0.0)
 if int(elapsed)!=before: changed.emit()
