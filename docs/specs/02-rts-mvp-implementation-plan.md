# RTS MVP for hub1.8.4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a minimum playable commander-on-field RTS MVP inside the hub1.8.4 verification scene where the player controls one hero, submits deputy text commands, destroys enemy buildings, and triggers victory.

**Architecture:** Add five focused Unity modules on top of the existing `SharedOfficeWars` prototype: hero control, command console, match state, scene adapter, and MVP HUD. Reuse existing combat, faction, and HUD primitives where they help, but keep MVP-specific logic isolated under dedicated `RTSMVP` folders so the hub scene integration stays reversible.

**Tech Stack:** Unity 2022.3.x, C#, Unity Test Framework, UGUI/OnGUI, existing `SharedOfficeWars` combat/faction/input systems

---

## File Structure

### New files to create
- `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Hero/HeroController.cs` — single-hero mouse-first control wrapper and target/attack flow
- `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Hero/HeroStateView.cs` — exposes current hero state for HUD and debugging
- `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Command/DeputyChannel.cs` — enum for combat/economy channels
- `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Command/DeputyCommandRecord.cs` — authoritative MVP command data object
- `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Command/CommandConsoleState.cs` — submission/status lifecycle store for command history
- `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Match/EnemyBuildingMarker.cs` — explicit building registration marker for victory tracking
- `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Match/MatchStateController.cs` — authoritative enemy-building registry and victory trigger
- `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Scene/HubSceneMvpBootstrap.cs` — binds hero, HUD, buildings, and validation checks into hub1.8.4 scene
- `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/UI/MvpHudController.cs` — MVP HUD for hero state, command console, command log, voice placeholder, victory prompt
- `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/UI/VoicePlaceholderButton.cs` — explicit “coming soon” voice affordance behavior
- `unity/SharedOfficeWars/Assets/Tests/RTSMVP/EditMode/CommandConsoleStateTests.cs` — command console lifecycle tests
- `unity/SharedOfficeWars/Assets/Tests/RTSMVP/EditMode/MatchStateControllerTests.cs` — enemy building registry and one-shot victory tests
- `unity/SharedOfficeWars/Assets/Tests/RTSMVP/EditMode/HeroStateViewTests.cs` — hero state projection tests

### Existing files to modify
- `unity/SharedOfficeWars/Assets/Scripts/Combat/Health.cs` — emit destroy callbacks before object teardown so match state can update reliably
- `unity/SharedOfficeWars/Assets/Scripts/UI/EconomyHUD.cs` — either disable for MVP scene or hand off to new HUD without duplicate overlays
- `unity/SharedOfficeWars/Assets/Scripts/UI/DemoBootstrap.cs` — prevent demo auto-population from interfering with hub1.8.4 MVP scene
- `unity/SharedOfficeWars/Packages/manifest.json` — keep Unity Test Framework available if package drift appears

### Scene / prefab work
- `unity/SharedOfficeWars/Assets/Scenes/hub1.8.4.unity` (or the actual verified hub scene asset path once confirmed in project) — bind hero, enemy buildings, UI anchors, and bootstrap

---

## Task 1: Establish MVP data contracts and test scaffolding

**Files:**
- Create: `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Command/DeputyChannel.cs`
- Create: `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Command/DeputyCommandRecord.cs`
- Create: `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Command/CommandConsoleState.cs`
- Create: `unity/SharedOfficeWars/Assets/Tests/RTSMVP/EditMode/CommandConsoleStateTests.cs`

- [ ] **Step 1: Write the failing command console tests**

```csharp
using NUnit.Framework;
using SharedOfficeWars.RTSMVP.Command;

public class CommandConsoleStateTests {
  [Test]
  public void SubmitCommand_CreatesOrderedRecordWithSubmittedStatus() {
    var state = new CommandConsoleState();

    var record = state.Submit(DeputyChannel.Combat, "focus fire on enemy hq");

    Assert.AreEqual(DeputyCommandStatus.Submitted, record.Status);
    Assert.AreEqual(1, state.Recent.Count);
    Assert.AreEqual("focus fire on enemy hq", state.Recent[0].Text);
  }

  [Test]
  public void AdvanceStatus_PromotesCommandToPendingExecution() {
    var state = new CommandConsoleState();
    var record = state.Submit(DeputyChannel.Economy, "prepare second depot");

    state.MarkReceived(record.Id);
    state.MarkPendingExecution(record.Id);

    Assert.AreEqual(DeputyCommandStatus.PendingExecution, state.Recent[0].Status);
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Unity Test Runner -> EditMode -> CommandConsoleStateTests`
Expected: FAIL because MVP command state classes do not exist yet

- [ ] **Step 3: Write minimal implementation for command contracts and state store**

```csharp
namespace SharedOfficeWars.RTSMVP.Command {
  public enum DeputyChannel { Combat, Economy }
  public enum DeputyCommandStatus { Submitted, Received, PendingExecution }
}
```

```csharp
public sealed class CommandConsoleState {
  private readonly List<DeputyCommandRecord> _recent = new();
  private int _nextId = 1;
  public IReadOnlyList<DeputyCommandRecord> Recent => _recent;

  public DeputyCommandRecord Submit(DeputyChannel channel, string text) { /* create ordered record */ }
  public void MarkReceived(int id) { /* set status */ }
  public void MarkPendingExecution(int id) { /* set status */ }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Unity Test Runner -> EditMode -> CommandConsoleStateTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Command unity/SharedOfficeWars/Assets/Tests/RTSMVP/EditMode/CommandConsoleStateTests.cs
git commit -m "feat: add rts mvp command console state contracts"
```

---

## Task 2: Add hero state projection and safe mouse-first hero control

**Files:**
- Create: `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Hero/HeroController.cs`
- Create: `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Hero/HeroStateView.cs`
- Create: `unity/SharedOfficeWars/Assets/Tests/RTSMVP/EditMode/HeroStateViewTests.cs`
- Reference: `unity/SharedOfficeWars/Assets/Scripts/Input/PlayerInputController.cs`
- Reference: `unity/SharedOfficeWars/Assets/Scripts/Combat/Weapon.cs`

- [ ] **Step 1: Write the failing hero state tests**

```csharp
[Test]
public void HeroStateView_ReportsCurrentTargetAndLockState() {
  var state = new HeroStateView();
  state.Bind("Commander", 120f, 90f, true, "EnemyHQ");

  Assert.AreEqual("Commander", state.DisplayName);
  Assert.AreEqual("EnemyHQ", state.TargetName);
  Assert.IsTrue(state.CanAcceptInput);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Unity Test Runner -> EditMode -> HeroStateViewTests`
Expected: FAIL because `HeroStateView` does not exist yet

- [ ] **Step 3: Write minimal implementation for hero state + controller**

```csharp
public sealed class HeroStateView {
  public string DisplayName { get; private set; } = string.Empty;
  public float MaxHp { get; private set; }
  public float CurrentHp { get; private set; }
  public bool CanAcceptInput { get; private set; }
  public string TargetName { get; private set; } = "None";

  public void Bind(string displayName, float maxHp, float currentHp, bool canAcceptInput, string targetName) { /* set fields */ }
}
```

```csharp
public sealed class HeroController : MonoBehaviour {
  [SerializeField] private Camera cam = null!;
  [SerializeField] private UnitController hero = null!;
  [SerializeField] private LayerMask groundMask;

  public void SetLocked(bool locked) { /* suppress input after victory */ }
  public HeroStateView Snapshot() { /* project current health/target state */ }
}
```

- [ ] **Step 4: Run tests and do one in-editor smoke check**

Run: `Unity Test Runner -> EditMode -> HeroStateViewTests`
Expected: PASS

Run: `Play hub1.8.4 scene -> left click ground / enemy building`
Expected: Hero moves on valid ground, ignores invalid clicks safely, and can target enemy buildings

Progress note (2026-04-02): code updated so hero input now rejects same-faction targets and ignores clicks over the MVP command panel before issuing world orders.

- [ ] **Step 5: Commit**

```bash
git add unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Hero unity/SharedOfficeWars/Assets/Tests/RTSMVP/EditMode/HeroStateViewTests.cs
git commit -m "feat: add mouse-first hero controller for rts mvp"
```

---

## Task 3: Build command console lifecycle and voice placeholder UI behavior

**Files:**
- Modify: `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Command/CommandConsoleState.cs`
- Create: `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/UI/VoicePlaceholderButton.cs`
- Create: `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/UI/MvpHudController.cs`
- Reference: `unity/SharedOfficeWars/Assets/Scripts/UI/DebugToast.cs`

- [ ] **Step 1: Write the failing HUD-facing command tests**

```csharp
[Test]
public void SubmitCommand_RejectsEmptyTextAndKeepsOrderingStable() {
  var state = new CommandConsoleState();

  Assert.Throws<System.ArgumentException>(() => state.Submit(DeputyChannel.Combat, "   "));
  var first = state.Submit(DeputyChannel.Combat, "hold mid");
  var second = state.Submit(DeputyChannel.Economy, "queue depot");

  Assert.Less(first.CreatedAtUnixMs, second.CreatedAtUnixMs);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Unity Test Runner -> EditMode -> CommandConsoleStateTests`
Expected: FAIL because validation/order guarantees are not implemented yet

- [ ] **Step 3: Implement command submission UI and voice placeholder behavior**

```csharp
public sealed class VoicePlaceholderButton : MonoBehaviour {
  public string PlaceholderMessage => "Voice command coming soon — current MVP supports text commands only.";
  public void Trigger() => DebugToast.Show(PlaceholderMessage, 1.8f);
}
```

```csharp
public sealed class MvpHudController : MonoBehaviour {
  public void Bind(CommandConsoleState commandState, HeroController heroController, MatchStateController matchState) { /* bind modules */ }
  public void SubmitSelectedChannel(string text) { /* submit -> received -> pending execution */ }
}
```

- [ ] **Step 4: Run tests and UI smoke check**

Run: `Unity Test Runner -> EditMode -> CommandConsoleStateTests`
Expected: PASS

Run: `Play hub1.8.4 scene -> submit one combat command and one economy command`
Expected: Both appear in HUD history with `Submitted -> Received -> Pending Execution` status progression and visible channel labels

- [ ] **Step 5: Commit**

```bash
git add unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Command/CommandConsoleState.cs unity/SharedOfficeWars/Assets/Scripts/RTSMVP/UI
git commit -m "feat: add rts mvp command console hud and voice placeholder"
```

---

## Task 4: Add authoritative enemy-building registry and one-shot victory flow

**Files:**
- Create: `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Match/EnemyBuildingMarker.cs`
- Create: `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Match/MatchStateController.cs`
- Create: `unity/SharedOfficeWars/Assets/Tests/RTSMVP/EditMode/MatchStateControllerTests.cs`
- Modify: `unity/SharedOfficeWars/Assets/Scripts/Combat/Health.cs`

- [ ] **Step 1: Write the failing match-state tests**

```csharp
[Test]
public void DestroyLastEnemyBuilding_TriggersVictoryOnce() {
  var match = new MatchStateController();
  match.RegisterEnemyBuilding("hq");
  match.RegisterEnemyBuilding("tower");

  match.MarkDestroyed("hq");
  match.MarkDestroyed("tower");
  match.MarkDestroyed("tower");

  Assert.AreEqual(0, match.EnemyBuildingsRemaining);
  Assert.IsTrue(match.IsVictory);
  Assert.IsTrue(match.IsMatchLocked);
  Assert.AreEqual(1, match.VictoryTriggerCount);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Unity Test Runner -> EditMode -> MatchStateControllerTests`
Expected: FAIL because match registry/victory controller does not exist yet

- [ ] **Step 3: Implement building registry + Health destroy callback integration**

```csharp
public sealed class MatchStateController : MonoBehaviour {
  public int EnemyBuildingsRemaining { get; private set; }
  public bool IsVictory { get; private set; }
  public bool IsMatchLocked { get; private set; }
  public int VictoryTriggerCount { get; private set; }

  public void RegisterEnemyBuilding(string id) { /* authoritative registry */ }
  public void MarkDestroyed(string id) { /* decrement once and trigger victory */ }
}
```

```csharp
public sealed class Health : MonoBehaviour {
  public event System.Action<Health>? Destroyed;
  public void Damage(float amount) {
    // invoke Destroyed before Destroy(gameObject)
  }
}
```

- [ ] **Step 4: Run tests and scene verification**

Run: `Unity Test Runner -> EditMode -> MatchStateControllerTests`
Expected: PASS

Run: `Play hub1.8.4 scene -> destroy all registered enemy buildings`
Expected: Victory fires exactly once, input locks, and enemy building count reaches zero

- [ ] **Step 5: Commit**

```bash
git add unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Match unity/SharedOfficeWars/Assets/Tests/RTSMVP/EditMode/MatchStateControllerTests.cs unity/SharedOfficeWars/Assets/Scripts/Combat/Health.cs
git commit -m "feat: add rts mvp match state and victory tracking"
```

---

## Task 5: Integrate MVP modules into the hub1.8.4 scene with localized bootstrap

**Files:**
- Create: `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Scene/HubSceneMvpBootstrap.cs`
- Modify: `unity/SharedOfficeWars/Assets/Scripts/UI/DemoBootstrap.cs`
- Modify: `unity/SharedOfficeWars/Assets/Scripts/UI/EconomyHUD.cs`
- Modify: `unity/SharedOfficeWars/Assets/Scenes/hub1.8.4.unity` (or confirmed equivalent scene asset path)

- [ ] **Step 1: Write the failing initialization checklist as executable bootstrap assertions**

```csharp
void Start() {
  AssertReference(hero, "Hero binding missing in hub1.8.4 MVP bootstrap");
  AssertReference(matchState, "Match state missing in hub1.8.4 MVP bootstrap");
  AssertReference(commandState, "Command console missing in hub1.8.4 MVP bootstrap");
  AssertEnemyBuildingsRegistered();
}
```

- [ ] **Step 2: Run scene to verify it currently fails fast**

Run: `Play hub1.8.4 scene with bootstrap attached`
Expected: Visible initialization error for any missing hero/UI/building binding instead of silent failure

- [ ] **Step 3: Implement localized scene adapter and disable conflicting demo bootstrap paths**

```csharp
public sealed class HubSceneMvpBootstrap : MonoBehaviour {
  [SerializeField] private HeroController heroController = null!;
  [SerializeField] private CommandConsoleState commandState = null!;
  [SerializeField] private MatchStateController matchState = null!;
  [SerializeField] private MvpHudController hud = null!;
  [SerializeField] private EnemyBuildingMarker[] enemyBuildings = null!;

  void Start() {
    // validate, bind, subscribe, initialize HUD and victory lock
  }
}
```

Progress note (2026-04-02): bootstrap lifecycle was hardened so validation happens before runtime wiring, match/health subscriptions are added on enable and removed on disable, and repeated enable/disable cycles no longer stack duplicate victory/destroy handlers.

- [ ] **Step 4: Run full initialization + interaction smoke test**

Run: `Play hub1.8.4 scene`
Expected: Hero appears, HUD appears, command UI appears, enemy buildings are registered, and no duplicate economy/demo HUD overlays remain

- [ ] **Step 5: Commit**

```bash
git add unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Scene unity/SharedOfficeWars/Assets/Scripts/UI/DemoBootstrap.cs unity/SharedOfficeWars/Assets/Scripts/UI/EconomyHUD.cs unity/SharedOfficeWars/Assets/Scenes/hub1.8.4.unity
git commit -m "feat: wire rts mvp systems into hub scene"
```

---

## Task 6: Final verification pass, debug visibility, and acceptance checklist

**Files:**
- Modify: `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Hero/HeroController.cs`
- Modify: `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Command/CommandConsoleState.cs`
- Modify: `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/Match/MatchStateController.cs`
- Modify: `docs/superpowers/plans/2026-04-02-rts-mvp-implementation.md`

- [ ] **Step 1: Add minimum debug logs for all required events**

```csharp
Debug.Log("[RTSMVP] Hero input event: move/target accepted");
Debug.Log($"[RTSMVP] Command submitted: {record.Channel} -> {record.Text}");
Debug.Log($"[RTSMVP] Command status updated: {record.Id} -> {record.Status}");
Debug.Log($"[RTSMVP] Enemy building destroyed: {buildingId}");
Debug.Log("[RTSMVP] Victory triggered");
```

- [ ] **Step 2: Run edit mode test suite**

Run: `Unity Test Runner -> EditMode -> RTSMVP`
Expected: PASS for command, hero state, and match-state test groups

- [ ] **Step 3: Run the full acceptance flow manually in hub1.8.4 scene**

Run: `Play hub1.8.4 scene and verify acceptance criteria items 1-8 from the approved spec`
Expected: Full loop works from scene load -> hero control -> deputy command entry -> enemy building destruction -> victory lock

- [ ] **Step 4: Update plan checkboxes/results notes**

```markdown
- [ ] Acceptance flow verified in editor play mode on hub1.8.4 scene
- [ ] No duplicate victory trigger observed
- [ ] Voice placeholder is explicit and non-deceptive
```

- [ ] **Step 5: Commit**

```bash
git add unity/SharedOfficeWars/Assets/Scripts/RTSMVP docs/superpowers/plans/2026-04-02-rts-mvp-implementation.md
git commit -m "chore: verify rts mvp acceptance flow"
```

---

## Open Questions / Preconditions

1. Confirm the exact scene asset path for the “hub1.8.4 verification scene”. The spec names it, but the tracked repo snapshot does not expose a `.unity` scene file yet.
2. Confirm whether MVP HUD should fully replace `EconomyHUD` in this scene, or coexist with a trimmed-down economy strip.
3. Confirm whether the existing `UnitController` movement/attack behavior is sufficient for the hero, or whether hub1.8.4 needs NavMesh/pathing specifics beyond current prototype movement.

## Acceptance Mapping

- **Hero control module:** Task 2
- **Command console module:** Tasks 1 + 3
- **Match state module:** Task 4
- **Scene adapter module:** Task 5
- **MVP HUD/UI layer:** Task 3 + Task 5
- **Final spec acceptance:** Task 6

Plan complete and saved to `docs/superpowers/plans/2026-04-02-rts-mvp-implementation.md`.

Two execution options:

**1. Subagent-Driven (recommended)** - dispatch a fresh subagent per task, review between tasks, faster but more orchestration.

**2. Inline Execution** - execute tasks in this session step by step using this plan.
