# Single-Entity Location Save + Action Editor Labels — Design Spec

**Status:** Design approved, ready for implementation planning.
**Repo:** `thingsboard` / `ui-ngx` (Angular frontend). **No Flutter app or backend changes** — see "Mobile app impact" below.
**Branch:** `feat/gps-tracker` (nothing here is released; see "Compatibility").
**Origin:** Review of the mobile action editor for `Get phone location`, which surfaced (a) two different fields both labelled "Target entity", and (b) the question of whether multi-entity save is a feature worth keeping.

## Goal

Make **all three** location widget actions save to exactly **one** target entity, failing loudly when the configuration resolves to more, and clean up the action editor labels that the current wording made ambiguous.

The three actions:

| Action | Where | Multiplicity today |
|---|---|---|
| `getLocation` (with *Save location to entity* on) | `mobileAction` | up to 100 entities via alias fan-out |
| `saveBrowserLocation` | generic widget action | up to 100 entities via alias fan-out |
| `startLiveLocation` | `mobileAction` | 1 — silently takes the alphabetically first |

After this change all three behave identically: **one target, or an error.**

## Rationale

**A location fix is an observation about one physical body** — the phone, or the browser's host machine. Fan-out writes that single observation as N identical observations. A dashboard consuming the result cannot distinguish *"these 40 assets are genuinely at this spot"* from *"someone picked the wrong alias"*: all N receive byte-identical lat/lng from one sensor, with no aggregation and no per-entity differentiation. Fan-out is meaningful for *intent* (a command, a setpoint); it is not meaningful for a *measurement* of one thing.

**The multi path is easy to hit by accident, and it congratulates you for it.** Most useful alias filter types resolve to sets by nature (`deviceType`, `assetType`, `relationsQuery`, `entityList`); the single-resolving ones (`singleEntity`, `stateEntity`) are the minority. Today a user who picks a set-valued alias gets a green success toast — *"Browser location saved to 40 entities"* — confirming the mistake. Silent wrongness with positive feedback, at write scale.

**The 100-entity cap shows it was never a designed capability.** `aliasTargetsPageSize = 100` (`location.service.ts:74`), `totalTargets = max(totalElements, targets.length)` (`:269`) and the `location-saved-partial` warning exist only to bound an accident. An alias resolving 5,000 entities writes to 100 of them, ordered alphabetically by name, and warns. That is truncation, not a feature.

**Single → multi is the reversible direction.** Adding fan-out later is additive (restore `saveToTargets`, gate it behind an explicit opt-in). Removing it later breaks customer dashboards. With no use case in hand, take the reversible option.

**The one real use case is served differently.** Co-moving targets — a technician's phone writing to both their user entity and "Van 12" — wants 2–3 *deliberately named* targets, not an alias that happens to resolve to 2. That is a separate, cheaper feature if it is ever requested. Recorded under "Out of scope".

## Compatibility

**Nothing is shipped, so there is no migration.** `location.service.ts` was introduced in `f204f3f778b`; `git branch --contains` on that commit lists only `feat/gps-tracker`. On `master`, `WidgetMobileActionType.getLocation` carries only `getLocationFunction` — no `targetEntity`, no `saveToEntity`, no key mappings — and `saveBrowserLocation` does not exist. No dashboard in the wild can depend on fan-out.

## Behaviour: one target, two layers of feedback

Runtime resolution can only be checked at click time, so a runtime error is unavoidable. But `resolveMultiple` is a **static property of the alias filter** (`EntityAliasFilter.resolveMultiple`, `alias.models.ts:185-188`), not data-dependent, and the editor already holds every alias definition. So the misconfiguration is caught earlier as well.

### Layer 1 — config-time warning (soft, non-blocking)

In `LocationTargetEntityComponent`, when the selected alias's filter has `resolveMultiple === true`, show a warning next to the *Alias name* row:

> This alias can resolve to multiple entities. Saving will fail unless it resolves to exactly one.

**Soft, not a validation error.** A `deviceType` alias may legitimately match exactly one device today; blocking Save would be wrong. It informs, it does not prevent.

The component already fetches the data it needs — `this.entityAliases = this.callbacks?.fetchEntityAliases?.()` (`location-target-entity.component.ts:155`) — and already looks aliases up by name in `updateAttributeSourceEntityFilter` (`:232-247`). Reuse that lookup; both `source` and `aliasName` already have `valueChanges` subscriptions to hang recomputation on.

**Applies in both modes.** In *From attribute* mode the alias identifies the entity the attribute is *read from*, and `resolveAttributeSourceEntity` (`location.service.ts:346`) resolves it through the same single-alias path. A set-valued alias is equally ambiguous there. Since the warning attaches to the shared *Alias name* row (`location-target-entity.component.html:49-82`), one implementation covers both.

### Layer 2 — runtime error (hard)

`resolveSingleEntityAlias` (`location.service.ts:359`) currently queries `findAliasEntities(aliasInfo, 1)` and takes `page.data[0]`, which is precisely what makes over-resolution invisible. Change it to request **pageSize 2** and branch on the count:

| Resolved count | Outcome |
|---|---|
| 0 | existing `error-alias-not-resolved` |
| 1 | proceed |
| > 1 | new `error-alias-multiple`, reporting the count |

Count as `max(page.totalElements ?? 0, page.data.length)` so the message reports the true total rather than the page size when the server supplies it.

Two notes on `findAliasEntities` (`:286`): the page size only affects its `resolveMultiple === true` branch — a non-multiple alias short-circuits to `aliasInfo.currentEntity` as a one-element page and can never trip the new error. And with `resolveEntityAliasTargets` deleted it drops to a single caller, so the `pageSize` parameter may be inlined as a constant if the implementer prefers.

Rename the method to `resolveEntityAlias` — with fan-out gone, "single" is no longer a distinguishing qualifier.

This one change covers all three actions, because every path now funnels through `resolveTargetEntity` (`:317`).

## Code changes

### `ui-ngx/src/app/core/services/location.service.ts`

**Delete:**

- `LocationTargetResolution` interface (`:68-71`)
- `resolveTargets` (`:240-251`) and its `resolveNames` parameter
- `resolveEntityAliasTargets` (`:253-273`)
- `saveToTargets` (`:429-443`)
- `aliasTargetsPageSize` (`:74`) and `saveConcurrency` (`:77`)
- the now-unused `from` / `mergeMap` / `toArray` imports if nothing else needs them

**Rewire the two savers** to `resolveTargetEntity` → `saveKeys` (`:445`), which already writes attributes and time series for one entity:

- `saveMobileActionLocation` (`:95`) keeps `resolveTargetEntityName` (`:373`) — `LiveTrackingSaveInfo.targetName` needs it — and its `targetName` becomes that single name instead of a joined list.
- `saveBrowserLocation` (`:125`) never needed the name (it passed `resolveNames = false`), so it calls `resolveTargetEntity` → `saveKeys` and skips name resolution entirely.

**Simplify the browser toasts** (`:156-181`): the partial and multi branches go away, leaving `location-saved-keys` when keys were written and `location-saved` otherwise. A failed save keeps its existing error toast.

**`liveTrackingArgs` (`:186`)** inherits the new error for free — it already calls `resolveTargetEntity`, so its previous silent alphabetically-first pick is fixed as a side effect. But it does need a `catchError` of its own, because otherwise the error would be **invisible**. See "The `startLiveLocation` error sink" below.

### `location-target-entity.component.ts` / `.html`

- Add the config-time warning described above.
- **Remove the `panelHint` input** (`.ts:114-115`) and the `@if (panelHint)` branch in the template (`.html:20-24`). Its only caller was the live-tracking hint, which this design deletes; the panel title collapses to the unconditional form.
- Split the double-used title/label key (see Labels).

### `mobile-action-editor.component.html`

- Drop `panelHint="..."` from the `startLiveLocation` usage (`:85`). Nothing else changes here — the toggle (`:68`) and both keys-table titles (`:75`, `:88`) keep their current keys and text.

### `save-browser-location-action-editor.component.html`

- No changes. Its keys-table title (`:21`) is unaffected, and it never passed `panelHint`.

## Labels

**Scope: duplication only.** Once saving is single-entity, *"to entity"* is no longer factually wrong — it becomes accurate. So the wordiness-driven renames are dropped: **`save-to-entity` ("Save location to entity") and `location.saved-keys` ("Keys that are saved to entity") stay exactly as they are.**

The genuine defect is the duplication: the panel title and the source row label are the *same* i18n key, `widget-action.mobile.target-entity-type`, rendered at `location-target-entity.component.html:21`/`:23` and again at `:36-37`. Splitting it needs two distinct strings, so both sides of the split are in scope. The `CURRENT_ENTITY` dropdown option is also renamed, for accuracy rather than brevity (see below).

| Element | Key | Now | New |
|---|---|---|---|
| Save toggle (`getLocation`) | `widget-action.mobile.save-to-entity` | Save location to entity | *unchanged* |
| Panel title | *new:* `widget-action.mobile.target-panel-title` | — | **Target** |
| Source row label | `target-entity-type` → *rename to* `target-save-to` | Target entity | **Save to** |
| Source dropdown option | `widget-action.mobile.target-current-entity` | Current datasource | **Entity from widget datasource** |
| Keys table title | `widget-action.location.saved-keys` | Keys that are saved to entity | *unchanged* |

Renaming the key `target-entity-type` → `target-save-to` is a two-line change (the key is referenced only in that one template, never in `location.models.ts`) and avoids leaving a key named `-entity-type` holding the text "Save to".

Resulting panel for *Get phone location*:

```
Save location to entity  ⏺
  Target                    [ Entity | From attribute ]
  Save to                   [ Entity from widget datasource ▾ ]
  Alias name                [ … ]        ← warning here when alias is set-valued
  ┌ Keys that are saved to entity ─────┐
  │ Argument │ Data key │ Type         │
```

In *From attribute* mode the row label continues to switch to `target-attribute-source` ("Read attribute from"), unchanged.

### Why "Entity from widget datasource" for `CURRENT_ENTITY`

`"Current datasource"` had two problems: `"current"` never said *whose* datasource on a dashboard full of widgets, and it named a *datasource* when the value is an *entity* — a datasource is a query that yields entities, not an entity itself.

The new label is accurate on every dispatch path, all of which take the entity from the widget's own datasource data:

- **Row-level actions** pass the clicked row's own `entity.id` straight into `handleWidgetAction` as `entityId` (`entities-table-widget.component.ts:804-808`, plus the timeseries-table cell and flot data-point equivalents), which becomes `currentEntityId` in the resolver.
- **Widget-level actions** (header action, widget click) go through `getActiveEntityInfo()` (`widget.component.ts:1793`), which reads `widgetContext.activeEntityInfo` — assigned in exactly one place in the tree, `timeseries-table-widget.component.ts:645`, from `this.sources[this.sourceIndex].datasource`, i.e. the currently selected datasource tab — and otherwise falls back to `subscription.getFirstEntityInfo()`.

It also parallels the naming of the existing `stateEntity` alias filter, `"Entity from dashboard state"`.

Alternatives considered and rejected:

- **"Entity from dashboard state"** — already taken, by an unrelated mechanism: `alias.filter-type-state-entity` (*"Entity taken from dashboard state parameters"*, `AliasFilterType.stateEntity`). `CURRENT_ENTITY` never reads state params.
- **"Current entity"** — matches `calculated-fields.argument-current` and the existing *"Widget action has no current entity"* error string, but keeps the vague `"current"` qualifier.
- **"Widget datasource"** — shorter and accurate about *whose* datasource, but still names a datasource when the value is an entity.

## Localization

`locale.constant-en_US.json` **only**. Verified: no other `locale.constant-*.json` contains `target-current-entity`, so none of these keys have been translated yet.

**Add:**

- `widget-action.location.error-alias-multiple` — *"Entity alias '{{alias}}' resolves to {{count}} entities. The location can only be saved to a single entity."*
- `widget-action.mobile.target-alias-multiple-warning` — *"This alias can resolve to multiple entities. Saving will fail unless it resolves to exactly one."*
- `widget-action.mobile.target-panel-title` — *"Target"*
- `widget-action.mobile.live-location-start-failed` — *"Failed to start live location tracking: {{error}}"*. A new key rather than reusing `location-save-failed` ("Failed to save location: …"), which would misdescribe a start failure.

**Rename:** `widget-action.mobile.target-entity-type` → `widget-action.mobile.target-save-to`, new value *"Save to"*. Its three template references (`location-target-entity.component.html:21`, `:23`, `:37`) collapse to one: `:21`/`:23` are the two `panelHint` branches that this design merges into a single unconditional title using the new `target-panel-title` key, leaving `:37` as the only `target-save-to` use.

**Change in place:** `widget-action.mobile.target-current-entity` → *"Entity from widget datasource"*. `save-to-entity` and `location.saved-keys` are deliberately left alone (see Labels).

**Remove:**

- `widget-action.browser-location.location-saved-keys-multi`
- `widget-action.browser-location.location-saved-partial`
- `widget-action.mobile.live-location-alias-hint` — asserted *"…uses the first one"*, which this design replaces with an error

## Mobile app impact

**None.** The Flutter app already models exactly one target: `LiveTrackingConfig.target` is a single `LiveTrackingTarget` (`lib/utils/services/live_location_tracking/model/live_tracking_config.dart:122-179`), and `_save` writes one telemetry and one attributes request per fix (`live_location_tracking_service.dart:310-339`). The web side already sends a single `target: {entityType, id}` (`location.service.ts:191-194`). This design makes the web editor and the one-shot savers consistent with what the app already does — the wire protocol is unchanged.

## Error handling

| Condition | Message | Surface |
|---|---|---|
| Alias not present on dashboard | `error-alias-not-found` (existing) | error toast |
| Alias resolves to 0 | `error-alias-not-resolved` (existing) | error toast |
| Alias resolves to >1 | `error-alias-multiple` (**new**) | error toast |
| `CURRENT_ENTITY` with no active entity | `error-no-current-entity` (existing) | error toast |
| Attribute-source problems | existing `error-attribute-*` family | error toast |
| Save request fails | `location-save-failed` (existing, per action) | error toast |
| Any of the above while starting live tracking | `live-location-start-failed` (**new**) wrapping the cause | error toast |

`saveMobileActionLocation` catches into a toast and completes without emitting; `saveBrowserLocation` reports through its `subscribe` error handler. Both are unchanged.

### The `startLiveLocation` error sink

`startLiveLocation` is the only action that resolves its target **during** bridge-args building rather than after, and that phase's error sink discards everything. An uncaught error propagates to the `error` callback of `argsObservable.subscribe(...)` (`widget.component.ts:1496`), which wraps it as `` `Failed to get mobile action arguments: ${err.message}` `` and hands it to `handleWidgetMobileActionError` (`:1509`) — a method whose entire body is one `if (isNotEmptyTbFunction(mobileAction.handleErrorFunction))` with no `else`. With no custom *Handle error* function configured on the action, the message is **dropped**: no toast, no `console.error`, no session. The button appears dead.

That silence predates this design — it already swallows `error-alias-not-found`, `error-alias-not-resolved`, `error-no-current-entity` and the whole `error-attribute-*` family for live tracking. But making over-resolution a hard error adds a failure mode that is easy to hit by accident, which would convert the old *silently wrong* behaviour (tracking the alphabetically first entity) into *silently nothing* — strictly worse for the user, and the opposite of this design's goal.

The config-time warning does not cover it: that shows to whoever edits the dashboard, while the person tapping the button in the mobile app is often someone else.

**Fix:** give `liveTrackingArgs` the same treatment the other two savers already have — a trailing `catchError` that shows `live-location-start-failed` via `ctx.showErrorToast` and returns `EMPTY`, so the observable completes without emitting, `next` never fires, and no bridge call is made. All three actions then surface one clean localized toast, and the four pre-existing silent conditions are closed as a side effect.

## Testing

`ui-ngx` has one `.spec.ts` in the entire tree (`auth.service.spec.ts`), so unit tests are not the convention here. Verify manually, in the style of `docs/testing/`:

**Per action** — `getLocation` + *Save location*, `saveBrowserLocation`, `startLiveLocation`:

1. `Entity from widget datasource` on an entity widget → saves to the widget's active/first datasource entity; on a table row action, to the clicked row's entity.
2. `Current user` → saves to the user entity.
3. Alias with `resolveMultiple: false` → saves to the one entity, no warning shown.
4. Alias with `resolveMultiple: true` resolving to exactly **1** → **warning shown in editor, save succeeds**. This is the case that must not regress into a block.
5. Alias with `resolveMultiple: true` resolving to **many** → warning in editor; at click time an error toast naming the alias and the count; **no writes land on any entity**.
6. `From attribute` with a set-valued alias as the attribute source → same warning, same runtime error.

**Editor:** panel title and source row read differently ("Target" / "Save to") in all three editors; no live-tracking tooltip on the panel title for `startLiveLocation`.

**Regression:** an action configured before this change (target + keys already stored) still loads and saves — the stored `MobileActionTargetEntityConfig` shape is untouched.

## Out of scope

- **Explicit multi-target save** (a small, deliberately named target list, capped low). The plausible co-move use case; revisit only on a concrete request.
- **Multi-entity live tracking** — remains out of scope for the reasons in `2026-07-22-gps-live-tracking-ux-design.md:17`, now reinforced: 2N requests per fix for the whole session duration, and contested `GPS_ACTIVE` / `GPS_TRACKED_BY` flags between overlapping sessions.
- **Translating the new strings** into the other 27 locale files.
- **Mid-session alias re-resolution.**
