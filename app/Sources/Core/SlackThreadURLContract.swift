/// The URL contract shared by the parser, shortcut generator, and bundle registration checks.
public enum SlackThreadURLContract {
    public static let scheme = "terminal-checkout"
    public static let host = "slack-thread"
    public static let queryKey = "url"
    public static let shortcutURLPrefix = "\(scheme)://\(host)?\(queryKey)="
}
