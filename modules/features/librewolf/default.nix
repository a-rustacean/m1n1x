{ ... }: {
  flake.nixosModules.librewolf =
    { pkgs, ... }:
    let
      mkPluginUrl = id: "https://addons.mozilla.org/firefox/downloads/latest/${id}/latest.xpi";

      mkExtensionEntry =
        {
          id,
          pinned ? false,
        }:
        let
          base = {
            install_url = mkPluginUrl id;
            installation_mode = "force_installed";
            private_browsing = true;
          };
        in
        if pinned then base // { default_area = "navbar"; } else base;

      mkExtensionSettings = builtins.mapAttrs (
        _: entry: if builtins.isAttrs entry then entry else mkExtensionEntry { id = entry; }
      );
    in
    {
      programs.firefox = {
        enable = true;
        package = pkgs.librewolf;
        policies = {
          DisableTelemetry = true;
          DisableFirefoxStudies = true;
          NoDefaultBookmarks = true;
          FirefoxSuggest = {
            WebSuggestions = false;
            SponsoredSuggestions = false;
            OnlineEnabled = false;
            Locked = true;
          };
          Preferences = {
            "privacy.donottrackheader.enabled" = true;
            "privacy.fingerprintingProtection" = true;
            "privacy.resistFingerprinting" = true;
            "privacy.trackingprotection.emailtracking.enabled" = true;
            "privacy.trackingprotection.enabled" = true;
            "privacy.trackingprotection.fingerprinting.enabled" = true;
            "privacy.trackingprotection.socialtracking.enabled" = true;

            "ui.systemUsesDarkTheme" = "1";

            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          };
          ExtensionSettings = mkExtensionSettings {
            # Extension to get IDs of other extensions
            "queryamoid@kaply.com" = {
              install_url = "https://github.com/mkaply/queryamoid/releases/download/v0.2/query_amo_addon_id-0.2-fx.xpi";
              installation_mode = "force_installed";
              default_area = "navbar";
              private_browsing = true;
            };
            "uBlock0@raymondhill.net" = mkExtensionEntry {
              id = "ublock-origin";
              pinned = true;
            };
            "{85860b32-02a8-431a-b2b1-40fbd64c9c69}" = "github-file-icons";
            "{74145f27-f039-47ce-a470-a662b129930a}" = "clearurls";
            "github-no-more@ihatereality.space" = "github-no-more";
            "github-repository-size@pranavmangal" = "gh-repo-size";
            "@searchengineadremover" = "searchengineadremover";
            "jid1-KKzOGWgsW3Ao4Q@jetpack" = "i-dont-care-about-cookies";
            "sponsorBlocker@ajay.app" = "sponsorblock";
          };
        };
      };
      environment.etc."firefox/policies/policies.json".target = "librewolf/policies/policies.json";
    };
}
