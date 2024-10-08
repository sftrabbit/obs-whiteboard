# Whiteboard Source for OBS

This script adds a whiteboard source type to OBS that allows users to annotate their stream/recording while live.

Supports the following features:
- Annotate your video while recording/streaming.
- Change brush color and size, or use the eraser to remove brush strokes.
- Switch to arrow mode to automatically add an arrow head to the end of your line.
- Easily undo previously drawn lines or clear the whole whiteboard.

*Note*: Currently only supports Windows.

![A screenshot of the OBS Whiteboard script being used in OBS. There are two desktop windows side by side. The window on the right is OBS Studio configured to show the whiteboard on top of the scene. The window on the left is a projector window, on which the word "Hello!", a smiley face, and some arrows have been drawn in various colours and sizes.](obs-whiteboard-screenshot.jpg?raw=true)

You can see an example of me using this script to annotate a puzzle game in [one of my YouTube videos](https://youtu.be/2E8IpCd0v9c?si=7hIhhYy6b2JsacVv&t=127).

This is a fork of [Mike Welsh](https://github.com/Herschel/)'s original script.

## How to use

1. Download [the latest version of this script](https://github.com/sftrabbit/obs-whiteboard/releases) and extract the zip file wherever you like.
2. Go to Tools > Scripts in OBS, then click the + button at the bottom of your list of scripts.
3. Select the `main.lua` file in the directory you extracted earlier to add it as a script.
4. In the main OBS window, click the + button below your list of sources and then select "Whiteboard". *(Note: you may have to toggle the visibility of the whiteboard on/off once to activate it)*
5. In the main OBS window, right click your scene and select "Windowed Projector".
6. Draw on the projector window by left clicking

The following keys can be used while the projector window is focused:
- `1-9`: select brush color
- `0`: select eraser
- `+` or `-`: increase or decrease the size of your brush/eraser
- `e`: toggle between brush and eraser
- `a`: toggle brush to or from arrow mode
- backspace: undo previous change
- `c`: clear whiteboard (this cannot be undone)

*Note*: For convenience, when switching to the eraser, the eraser size is automatically set to a size bigger than the current brush.

## Known issues

- Keyboard shortcuts are currently not configurable.
- The script can crash if reloaded while active. That is, by clicking the "refresh" button in the Tools > Scripts window.
  * This is due to a bug in OBS that only occurs with scripts that define their own source types. In certain situations, a deadlock can occur between the UI thread and the rendering thread.
- Whiteboard source doesn't accept inputs after being added to a scene, or after the script is refreshed.
  * This is because the source is only interactable when it's active. There's unfortunately no way to check whether a source is currently active, so we rely on the triggers on transition between active and deactive to determine when to enable interaction. Certain situations do not trigger this transition (e.g. adding a new source, refreshing the script, etc.), hence the source never knows it's active.


## Authors

- **mwelsh** *([TILT forums](http://tiltforums.com/u/mwelsh))* *([GitHub](https://github.com/Herschel/obs-whiteboard))*  
- **Tari**  
- **Joseph Mansfield** *([GitHub](https://github.com/sftrabbit))* *([YouTube](https://youtube.com/@JoePlaysPuzzleGames))* *([josephmansfield.uk](https://josephmansfield.uk))*

