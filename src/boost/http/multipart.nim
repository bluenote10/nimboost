## The module implements asynchronous handling of the multipart
## messages.
##

import ./httpcommon,
       asyncdispatch,
       ../io/asyncstreams,
       strutils,
       ../data/props,
       ../data/memory

type
  MultiPartMessage* = ref object
    s: AsyncStream
    ct: ContentType
    finished: bool
    boundary: string
  MessagePart* = ref object
    msg: MultiPartMessage
    h: Props
    ct: ContentType
    cd: ContentDisposition
    enc: string
    cl: int

proc open*(t: typedesc[MultiPartMessage], s: AsyncStream, contentType: ContentType): MultiPartMessage =
  ## Opens multipart message with ``contentType`` for reading from stream ``s``.
  if not contentType.mimeType.startsWith("multipart"):
    raise newException(ValueError, "MultiPartMessage can't handle this mime-type: " & contentType.mimeType)
  if contentType.boundary.len == 0:
    raise newException(ValueError, "ContentType boundary is absent")
  MultiPartMessage(s: newAsyncBufferedStream(s), ct: contentType, boundary: "--" & contentType.boundary)

proc atEnd*(m: MultiPartMessage): bool =
  m.finished

proc readNextPart*(m: MultiPartMessage): Future[MessagePart] {.async.} =
  ## Returns the next part of the message ``m`` or nil if it's ended
  if m.atEnd:
    return
  let s = m.s
  var line = await s.readLine
  if line.len == 0:
    m.finished = true
    return
  if not line.startsWith(m.boundary):
    m.finished = true
    return
  if line.endsWith("--"):
    m.finished = true
    return
  let headers = await s.readHeaders
  result = MessagePart(msg: m, h: headers, enc: "", cl: -1)
  for k, v in headers:
    if k.cmpIgnoreCase("Content-Type") == 0:
      result.ct = v.parseContentType
    elif k.cmpIgnoreCase("Content-Disposition") == 0:
      result.cd = v.parseContentDisposition
    elif k.cmpIgnoreCase("Content-Transfer-Encoding") == 0:
      result.enc = v
    elif k.cmpIgnoreCase("Content-Length") == 0:
      result.cl = v.parseInt

type
  EndOfPartStream = ref EndOfPartStreamObj
  EndOfPartStreamObj = object of AsyncStream
    p: MessagePart
    s: AsyncStream # wrapAsyncStream doesn't support nested fields
    eop: bool  # end of part has beed riched

proc eopRead(s: AsyncStream, buf: pointer, size: int): Future[int] {.async.} =
  let es = (EndOfPartStream)s
  if es.eop:
    return 0
  let bytes = await es.peekBuffer(buf, size)
  if bytes == 0:
    #TODO: Throw UnexpectedEndOfFile?
    es.eop = true
    return 0
  var boundary = "\c\L" & es.p.msg.boundary
  let (pos, length) = findInMem(buf, bytes, addr boundary[0], boundary.len)
  if pos == -1:
    # End of part was not found
    result = await es.s.readBuffer(buf, bytes)
  else:
    result = await es.s.readBuffer(buf, pos)
    let tb = await es.peekData(boundary.len + 2)
    if tb == boundary & "\c\L":
      discard await es.s.readData(2)
      es.eop = true
    elif tb == boundary & "--" and (await es.peekData(boundary.len + 4)) == boundary & "--\c\L":
      discard await es.s.readData(2)
      es.eop = true
      es.p.msg.finished = true

proc eopAtEnd(s: AsyncStream): bool =
  s.EndOfPartStream.eop

proc newEndOfPartStream(p: MessagePart): EndOfPartStream =
  new result
  result.p = p
  # It's already buffered, see constructor of the MultiPartMessage
  result.s = p.msg.s

  wrapAsyncStream(EndOfPartStream, s)
  result.readImpl = cast[type(result.readImpl)](eopRead)
  result.atEndImpl = eopAtEnd

proc getPartDataStream*(p: MessagePart): AsyncStream =
  if p.isNil or p.msg.finished:
    raise newException(IOError, "Can't read multipart data, it's finished!")
  newEndOfPartStream(p)

proc headers*(p: MessagePart): Props =
  ## Returns http headers of the multipart message part ``p``
  p.h

proc encoding*(p: MessagePart): string =
  ## Returns the encoding of the multipart message part ``p``
  p.enc

proc contentType*(p: MessagePart): ContentType =
  ## Returns the content type of the multipart message part ``p``
  p.ct

proc contentDisposition*(p: MessagePart): ContentDisposition =
  ## Returns the content disposition of the multipart message part ``p``
  p.cd
