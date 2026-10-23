import AppKit
import SwiftUI
import MirasCore

@main
@MainActor
struct MirasApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
                .frame(minWidth: 960, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

@MainActor
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var showNewBottle = false
    @State private var showEngine = false
    @State private var editingGame: Game?
    @State private var search = ""
    @State private var stopBottle: Bottle?
    private let accent = Color(red: 0.65, green: 0.89, blue: 0.37)

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up.fill").foregroundStyle(accent).font(.title)
                    Text("miras").font(.system(size: 30, weight: .bold, design: .rounded))
                }.padding(.top, 24)
                Text("YOUR WINDOWS. YOUR MAC.").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                Text("BOTTLES").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 18)
                List(selection: $model.selection) {
                    ForEach(model.library.bottles) { bottle in
                        Label(bottle.name, systemImage: "shippingbox").tag(bottle.id)
                            .padding(.vertical, 6)
                    }
                }.listStyle(.sidebar)
                Button { showNewBottle = true } label: { Label("New bottle", systemImage: "plus") }
                    .disabled(!model.canRun)
                Button("Install new game…") { model.installNew() }.disabled(!model.canRun)
                Divider()
                Button { showEngine = true } label: {
                    Label(model.engineReady ? "Engine settings" : "Set up engine", systemImage: "gearshape")
                }
                HStack(spacing: 6) {
                    Circle().fill(model.engineReady ? accent : .orange).frame(width: 6, height: 6)
                    Text(model.engineReady ? "Engine connected" : "Engine required").font(.caption).foregroundStyle(.secondary)
                }.padding(.bottom, 16)
            }.padding(.horizontal, 16)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                if let bottle = model.selectedBottle {
                    libraryHeader(bottle)
                    Divider()
                    gameLibrary(bottle)
                } else {
                    welcome
                }
                Divider()
                HStack(spacing: 10) {
                    if !model.busy.isEmpty { ProgressView().controlSize(.small) }
                    Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Button("Data folder") { model.revealData() }.buttonStyle(.link).font(.caption)
                }.padding(16)
            }.background(Color(red: 0.075, green: 0.085, blue: 0.095))
        }
        .tint(accent)
        .sheet(isPresented: $showNewBottle) { NewBottleView() }
        .sheet(isPresented: $showEngine) { EngineView() }
        .sheet(item: $editingGame) { GameEditor(game: $0) }
        .alert("Miras", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("Stop all Windows programs in this bottle? Unsaved progress may be lost.", isPresented: Binding(get: { stopBottle != nil }, set: { if !$0 { stopBottle = nil } }), titleVisibility: .visible) {
            Button("Stop programs", role: .destructive) { if let bottle = stopBottle { model.stop(bottle) }; stopBottle = nil }
        }
    }

    private func libraryHeader(_ bottle: Bottle) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("GAME LIBRARY").font(.caption.weight(.medium)).foregroundStyle(accent)
                Spacer()
                Menu {
                    Button("Open bottle folder") { model.reveal(bottle) }
                    Button("Windows configuration") { model.configure(bottle) }.disabled(!model.canRun || model.busy[bottle.id] != nil)
                    if let log = model.logs[bottle.id] { Button("Open latest log") { NSWorkspace.shared.open(log) } }
                    Divider()
                    Button("Stop bottle programs", role: .destructive) { stopBottle = bottle }.disabled(!model.canRun)
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }.menuStyle(.borderlessButton).fixedSize()
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(bottle.name).font(.system(size: 34, weight: .bold))
                    Text("A separate Windows environment for your games.").foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.install(in: bottle) } label: { Label("Run installer", systemImage: "square.and.arrow.down") }
                    .disabled(!model.canRun || model.busy[bottle.id] != nil)
                Button { model.addGame(to: bottle) } label: { Label("Add game", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).foregroundStyle(.black)
                    .disabled(!model.storageReady || model.busy[bottle.id] != nil)
            }
            TextField("Search games", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
        }.padding(30)
    }

    private func gameLibrary(_ bottle: Bottle) -> some View {
        let games = model.library.games.filter { $0.bottleID == bottle.id && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
        return ScrollView {
            if games.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "gamecontroller").font(.system(size: 52, weight: .light)).foregroundStyle(accent)
                    Text(search.isEmpty ? "Make room for play." : "No matching games").font(.title2.bold())
                    Text(search.isEmpty ? "Run a Windows installer, then add the installed game's .exe.\nAlready have a game? Add its executable directly." : "Try another game name.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 90)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 18)], spacing: 18) {
                    ForEach(games) { game in
                        VStack(alignment: .leading, spacing: 16) {
                            ZStack {
                                LinearGradient(colors: [Color(red: 0.23, green: 0.32, blue: 0.24), Color(red: 0.12, green: 0.15, blue: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                Image(systemName: "gamecontroller.fill").font(.system(size: 54)).foregroundStyle(accent.opacity(0.8))
                            }.frame(height: 132).clipShape(RoundedRectangle(cornerRadius: 10))
                            Text(game.name).font(.headline).lineLimit(1)
                            Text(URL(fileURLWithPath: game.executable).lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            HStack {
                                Button { model.launch(game, in: bottle) } label: { Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity) }
                                    .buttonStyle(.borderedProminent).foregroundStyle(.black)
                                    .disabled(!model.canRun || model.busy[bottle.id] != nil)
                                Menu {
                                    Button("Edit game & arguments") { editingGame = game }
                                    Button("Show executable") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: game.executable)]) }
                                    Button("Remove from library", role: .destructive) { model.removeGame(game) }
                                } label: { Image(systemName: "ellipsis") }.fixedSize()
                            }
                        }.padding(16).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                    }
                }.padding(30)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("A new home\nfor your games.").font(.system(size: 54, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Text("Bring Windows games to your Mac with Wine.\nOne library. Separate bottles. Your own engine.").font(.title3).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button("1. Choose engine") { showEngine = true }.buttonStyle(.borderedProminent).foregroundStyle(.black)
                Button("2. Create a bottle") { showNewBottle = true }.disabled(!model.canRun)
            }
            Text("Compatibility varies by game and engine. Miras does not include Wine or a graphics translation layer.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: 460, alignment: .leading)
        }.padding(50).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

@MainActor
struct NewBottleView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var name = "My games"
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Create a bottle").font(.title2.bold())
            Text("Games in this bottle share a Windows drive and settings.").foregroundStyle(.secondary)
            TextField("Bottle name", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { model.createBottle(name: name); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.canRun)
            }
        }.padding(28).frame(width: 420)
    }
}

@MainActor
struct EngineView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var configuration = RuntimeConfiguration()
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your compatibility engine").font(.title2.bold())
            Text("Miras uses a separately installed macOS Wine engine. Choose its wine or wine64 binary. Some Intel engines also require Rosetta on Apple silicon.").foregroundStyle(.secondary)
            Text(model.library.enginePath.isEmpty ? "No engine selected" : model.library.enginePath)
                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("Find installed Wine") { model.discoverEngine() }
                Button("Choose binary…") { model.chooseEngine() }
            }.disabled(!model.storageReady || !model.busy.isEmpty)
            Group {
                Button("Import GPTK D3DMetal libraries…") { model.saveConfiguration(configuration); model.importD3DMetal() }
                Toggle("Engine already includes compatible D3DMetal", isOn: $configuration.d3dMetalReady)
                Toggle("Engine supports ESync", isOn: $configuration.supportsESync)
                Toggle("Engine supports MSync", isOn: $configuration.supportsMSync)
                HStack {
                    TextField("DXVK package folder (x64 / x32)", text: $configuration.dxvkPath)
                    Button("Browse…") { choosePath(directory: true) { configuration.dxvkPath = $0 } }
                }
                HStack {
                    TextField("Winetricks executable", text: $configuration.winetricksPath)
                    Button("Browse…") { choosePath(directory: false) { configuration.winetricksPath = $0 } }
                }
                Text("DXVK requires a macOS-compatible build and an engine with MoltenVK. Enable synchronization options only when supported by this engine.").font(.caption).foregroundStyle(.secondary)
            }.disabled(!model.busy.isEmpty || !model.storageReady)
            Link("Wine for macOS documentation", destination: URL(string: "https://gitlab.winehq.org/wine/wine/-/wikis/MacOS")!)
            Text("Use a compatible engine for each existing bottle. Changing engines can change or upgrade bottle data. Back up the data folder first.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { model.saveConfiguration(configuration); dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 520)
            .onAppear { configuration = model.library.configuration }
            .onChange(of: model.library.configuration) { configuration = $0 }
    }
    private func choosePath(directory: Bool, selected: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = directory
        panel.canChooseFiles = !directory
        if panel.runModal() == .OK, let url = panel.url { selected(url.path) }
    }
}

@MainActor
struct GameEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State var game: Game
    @State private var argumentLines = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Game settings").font(.title2.bold())
            TextField("Name", text: $game.name)
            TextField("Absolute executable path", text: $game.executable)
            Picker("Graphics", selection: $game.options.graphics) {
                ForEach(GraphicsBackend.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Synchronization", selection: $game.options.synchronization) {
                ForEach(Synchronization.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Toggle("Launch x86_64 Wine (Rosetta on Apple silicon)", isOn: $game.options.rosetta)
            Text("Install selected dependencies before launch").font(.caption)
            HStack {
                ForEach(WindowsDependency.allCases, id: \.self) { dependency in
                    Toggle(dependency.rawValue, isOn: Binding(get: { game.options.dependencies.contains(dependency) }, set: { selected in
                        game.options.dependencies.removeAll { $0 == dependency }
                        if selected { game.options.dependencies.append(dependency) }
                    }))
                }
            }
            Text("Launch arguments · one argument per line").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $argumentLines).font(.system(.body, design: .monospaced)).frame(height: 120)
            Text("Spaces inside a line are kept as part of that argument. Do not add shell quotes.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    game.arguments = argumentLines.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    model.updateGame(game); dismiss()
                }.keyboardShortcut(.defaultAction).disabled(game.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !game.executable.hasPrefix("/"))
            }
        }.textFieldStyle(.roundedBorder).padding(28).frame(width: 480)
            .onAppear { argumentLines = game.arguments.joined(separator: "\n") }
    }
}
