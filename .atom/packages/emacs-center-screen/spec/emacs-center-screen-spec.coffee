EmacsCenterScreen = require '../lib/emacs-center-screen'

# Use the command `window:run-package-specs` (cmd-alt-ctrl-p) to run specs.
#
# To run a specific `it` or `describe` block add an `f` to the front (e.g. `fit`
# or `fdescribe`). Remove the `f` to unfocus the block.

describe "EmacsStyleCenterScreen", ->
  activationPromise = null

  beforeEach ->
    atom.workspaceView = new WorkspaceView
    activationPromise = atom.packages.activatePackage('emacsCenterScreen')

  describe "when the emacs-center-screen:center-screen is triggered", ->
    it "should move the line the cursor is on to the top of the screen if not already there"
    it "should move the line the cursor is on to the bottom of the screen, if it's at the top"
