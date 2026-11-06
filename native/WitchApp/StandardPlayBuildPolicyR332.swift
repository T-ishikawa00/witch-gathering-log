/// Compile-time switches for the explicit local standard-play candidate.
/// Release builds remain ordinary unless STANDARD_PLAY_R169 is deliberately defined.
public enum StandardPlayBuildPolicyR332 {
    public static var standardPlayEnabled: Bool {
        #if STANDARD_PLAY_R169
        true
        #else
        false
        #endif
    }

    public static var firstCraftAidEnabled: Bool {
        #if STANDARD_PLAY_R169 && FIRST_CRAFT_AID_R179
        true
        #else
        false
        #endif
    }
}
