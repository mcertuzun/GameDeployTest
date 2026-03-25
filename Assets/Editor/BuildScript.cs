using UnityEditor;
using UnityEditor.Build.Reporting;
using System;

public class BuildScript
{
    static string[] GetScenes()
    {
        return new string[] { "Assets/Scenes/SampleScene.unity" };
    }

    public static void BuildIOS()
    {
        var options = new BuildPlayerOptions
        {
            scenes = GetScenes(),
            locationPathName = "Builds/iOS",
            target = BuildTarget.iOS,
            options = BuildOptions.None
        };
        var report = BuildPipeline.BuildPlayer(options);
        if (report.summary.result != BuildResult.Succeeded)
        {
            Console.WriteLine("iOS build failed!");
            EditorApplication.Exit(1);
        }
        EditorApplication.Exit(0);
    }

    public static void BuildAndroid()
    {
        PlayerSettings.Android.useCustomKeystore = false;
        var options = new BuildPlayerOptions
        {
            scenes = GetScenes(),
            locationPathName = "Builds/Android/game.apk",
            target = BuildTarget.Android,
            options = BuildOptions.None
        };
        var report = BuildPipeline.BuildPlayer(options);
        if (report.summary.result != BuildResult.Succeeded)
        {
            Console.WriteLine("Android build failed!");
            EditorApplication.Exit(1);
        }
        EditorApplication.Exit(0);
    }
}
