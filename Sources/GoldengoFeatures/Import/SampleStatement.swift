public enum SampleStatement {
    /// Demo data for "Try a sample statement". Includes a recurring monthly NETFLIX charge across
    /// three months so subscription detection (GOL-7) has something to surface, a one-off shop run,
    /// and a SALARY credit — which must NOT be flagged as a subscription (income is excluded).
    public static let csv = """
    Date,Description,Amount,Reference
    2026-03-15,NETFLIX,-1200.00,n1
    2026-04-15,NETFLIX,-1200.00,n2
    2026-05-15,NETFLIX,-1200.00,n3
    2026-05-30,SPAR TIRANA,-1500.00,s1
    2026-05-29,COFFEE CORNER,-250.00,s2
    2026-05-28,CONAD MARKET,-3200.00,s3
    2026-05-27,SALARY,45000.00,s4
    """
}
