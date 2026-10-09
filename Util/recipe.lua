local root = os.getenv("CM_BUILD_DIR") or os.getenv("GITHUB_WORKSPACE") or os.getenv("WORKSPACE")

return {
    appName = "SmartSheepCreator",
    platform = "ios",
    appVersion = os.getenv("APP_VERSION") or "1.0",
    projectPath = root,
    dstPath = root .. "/build",
    certificatePath = root .. "/Util/distribution.mobileprovision",
  --  customTemplate = "-angle",
}