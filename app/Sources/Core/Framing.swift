import Foundation

// Chrome Native Messaging 프레이밍: 4바이트 네이티브 엔디언(=LE) 길이 + JSON payload.
// relay↔앱 소켓 통신도 동일한 프레이밍을 쓴다.

private let maxFrameLength = 16 * 1024 * 1024

public func frameMessage(_ payload: Data) -> Data {
    var data = Data(capacity: payload.count + 4)
    let length = UInt32(payload.count)
    data.append(UInt8(truncatingIfNeeded: length))
    data.append(UInt8(truncatingIfNeeded: length >> 8))
    data.append(UInt8(truncatingIfNeeded: length >> 16))
    data.append(UInt8(truncatingIfNeeded: length >> 24))
    data.append(payload)
    return data
}

public func readFramedMessage(fromFD fd: Int32) -> Data? {
    guard let header = readExactly(fd: fd, count: 4) else { return nil }
    let length = Int(header[header.startIndex])
        | Int(header[header.startIndex + 1]) << 8
        | Int(header[header.startIndex + 2]) << 16
        | Int(header[header.startIndex + 3]) << 24
    guard length >= 0, length <= maxFrameLength else { return nil }
    if length == 0 { return Data() }
    return readExactly(fd: fd, count: length)
}

@discardableResult
public func writeFramedMessage(_ payload: Data, toFD fd: Int32) -> Bool {
    writeAll(fd: fd, data: frameMessage(payload))
}

private func readExactly(fd: Int32, count: Int) -> Data? {
    var data = Data()
    data.reserveCapacity(count)
    var buffer = [UInt8](repeating: 0, count: min(count, 65536))
    while data.count < count {
        let n = read(fd, &buffer, min(buffer.count, count - data.count))
        if n > 0 {
            data.append(contentsOf: buffer[0..<n])
        } else if n < 0 && errno == EINTR {
            continue
        } else {
            return nil
        }
    }
    return data
}

@discardableResult
public func writeAll(fd: Int32, data: Data) -> Bool {
    var offset = 0
    let bytes = [UInt8](data)
    while offset < bytes.count {
        let n = bytes.withUnsafeBufferPointer { buf in
            write(fd, buf.baseAddress! + offset, bytes.count - offset)
        }
        if n > 0 {
            offset += n
        } else if n < 0 && errno == EINTR {
            continue
        } else {
            return false
        }
    }
    return true
}
