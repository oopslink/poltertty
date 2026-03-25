// macos/Sources/GitKit/GitError.swift
import Foundation

enum GitError: Error, LocalizedError {
    case notARepository
    case libgit2(Int32, String)  // (error code, message)
    case invalidOid(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notARepository:
            return "Not a git repository"
        case .libgit2(let code, let msg):
            return "libgit2 error \(code): \(msg)"
        case .invalidOid(let oid):
            return "Invalid commit OID: \(oid)"
        case .operationFailed(let msg):
            return msg
        }
    }

    // libgit2 错误包装辅助函数
    static func fromLibgit2(_ code: Int32) -> GitError {
        let msg: String
        if let errPtr = git_error_last() {
            msg = String(cString: errPtr.pointee.message)
        } else {
            msg = "Unknown error"
        }
        return .libgit2(code, msg)
    }
}
