# GPS One-Shot Save (Phase 1b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the `getLocation` mobile action so a dashboard can declaratively save the phone's coordinates to a configurable target entity (attributes or timeseries) — no hand-edited JS.

**Architecture:** The save block is stored in the widget action descriptor (dashboard JSON). At click time the web runtime (`widget.component.ts`) receives lat/lng (+accuracy/ts) from the mobile app over the existing `tbMobileHandler` bridge, resolves the target entity (current entity / current user / alias by name / from attribute value), and saves via `AttributeService`. The mobile app change is payload-only. Fully backward compatible: `saveToEntity` absent → today's behavior; old mobile apps just omit accuracy/ts.

**Tech Stack:** Angular 18 reactive forms (ui-ngx), RxJS, Flutter/Dart.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-03-gps-tracking-design.md` (phase 1b section).
- ui-ngx repo: `/home/artem/projects/thingsboard`, branch `feat/gps-tracker`. Flutter repo: `/home/artem/projects/mobile/flutter_thingsboard_app`, branch `feat/gps-tracker`.
- Conventional Commits; **no** `Co-Authored-By` lines.
- Dart: run `dart format <changed files>` before committing; `flutter analyze` must stay clean for changed files.
- ui-ngx: no component unit-test harness is in active use for these widget-settings components; verification is `npx tsc --noEmit -p src/tsconfig.app.json` (type check) + manual smoke test (Task 5). This is the repo convention — do not scaffold karma tests.
- Alias targeting stores the alias **name** (plain text input), not an alias id picker: the editor (`WidgetActionCallbacks`) has no alias-controller access and is also used by the SCADA symbol editor where no dashboard aliases exist. Resolution happens at click time via `widgetContext.aliasController`.
- Default attribute/telemetry keys: `latitude` / `longitude`. Metadata keys (when enabled): `gpsAccuracy`, `gpsTimestamp`.

---

### Task 1: Flutter — add accuracy/ts to the location result payload

**Files:**
- Modify: `lib/utils/services/mobile_actions/results/location_result.dart`
- Modify: `lib/utils/services/mobile_actions/mobile_action_result.dart` (location factory)
- Modify: `lib/utils/services/mobile_actions/actions/location_action_result_mapper.dart`
- Test: `test/utils/services/mobile_actions/location_action_result_mapper_test.dart` (new; first test in the repo — `test/` does not exist yet)

**Interfaces:**
- Consumes: `GeoPosition` (`lib/utils/services/location/model/geo_position.dart`) — freezed, fields `latitude` (double), `longitude` (double), `accuracy` (double), `timestamp` (DateTime?).
- Produces: result JSON `{hasResult: true, result: {latitude, longitude, accuracy?, ts?}}` — Task 2's `MobileLocationResult` mirrors this; Task 4 reads `actionResult.accuracy` / `actionResult.ts`.

- [ ] **Step 1: Write the failing test**

Create `test/utils/services/mobile_actions/location_action_result_mapper_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_app/utils/services/location/model/geo_position.dart';
import 'package:thingsboard_app/utils/services/location/model/location_fix.dart';
import 'package:thingsboard_app/utils/services/mobile_actions/actions/location_action_result_mapper.dart';

class _Mapper with LocationActionResultMapper {}

void main() {
  test('LocationSuccess maps to success json with accuracy and ts', () {
    final result = _Mapper().mapLocationFixToResult(
      LocationSuccess(
        GeoPosition(
          latitude: 50.45,
          longitude: 30.52,
          accuracy: 12.5,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1720000000000),
        ),
      ),
    );

    final json = result.toJson();
    expect(json['hasResult'], true);
    expect(json['hasError'], false);
    expect(json['result']['latitude'], 50.45);
    expect(json['result']['longitude'], 30.52);
    expect(json['result']['accuracy'], 12.5);
    expect(json['result']['ts'], 1720000000000);
  });

  test('LocationSuccess without timestamp omits ts key', () {
    final result = _Mapper().mapLocationFixToResult(
      LocationSuccess(
        GeoPosition(latitude: 1, longitude: 2, accuracy: 3, timestamp: null),
      ),
    );

    final json = result.toJson();
    expect(json['result'].containsKey('ts'), false);
    expect(json['result']['accuracy'], 3);
  });

  test('LocationPermissionDenied maps to error result', () {
    final result =
        _Mapper().mapLocationFixToResult(const LocationPermissionDenied());

    final json = result.toJson();
    expect(json['hasError'], true);
    expect(json['hasResult'], false);
  });
}
```

Note: if `GeoPosition`'s constructor differs (check `lib/utils/services/location/model/geo_position.dart` — freezed, named params), adjust the test construction, not the assertions.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/artem/projects/mobile/flutter_thingsboard_app && flutter test test/utils/services/mobile_actions/location_action_result_mapper_test.dart`
Expected: FAIL — `json['result']['accuracy']` is null (payload has no accuracy key yet).

- [ ] **Step 3: Implement the payload extension**

`lib/utils/services/mobile_actions/results/location_result.dart` — replace the class body:

```dart
import 'package:thingsboard_app/utils/services/mobile_actions/mobile_action_result.dart';

class LocationResult extends MobileActionResult {
  LocationResult(this.latitude, this.longitude, {this.accuracy, this.ts});
  num latitude;
  num longitude;
  num? accuracy;
  int? ts;

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['latitude'] = latitude;
    json['longitude'] = longitude;
    if (accuracy != null) {
      json['accuracy'] = accuracy;
    }
    if (ts != null) {
      json['ts'] = ts;
    }
    return json;
  }
}
```

`lib/utils/services/mobile_actions/mobile_action_result.dart` — replace the location factory:

```dart
  factory MobileActionResult.location(
    num latitude,
    num longitude, {
    num? accuracy,
    int? ts,
  }) {
    return LocationResult(latitude, longitude, accuracy: accuracy, ts: ts);
  }
```

`lib/utils/services/mobile_actions/actions/location_action_result_mapper.dart` — replace the `LocationSuccess` arm:

```dart
      LocationSuccess(:final position) =>
        WidgetMobileActionResult.successResult(
          MobileActionResult.location(
            position.latitude,
            position.longitude,
            accuracy: position.accuracy,
            ts: position.timestamp?.millisecondsSinceEpoch,
          ),
        ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/utils/services/mobile_actions/location_action_result_mapper_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Format, analyze, commit**

```bash
cd /home/artem/projects/mobile/flutter_thingsboard_app
dart format lib/utils/services/mobile_actions/ test/
flutter analyze 2>&1 | grep -E "mobile_actions|location_" ; echo "expect no output above"
git add lib/utils/services/mobile_actions/ test/
git commit -m "feat(location): include accuracy and timestamp in getLocation action result"
```

---

### Task 2: ui-ngx — descriptor model + locale keys

**Files:**
- Modify: `ui-ngx/src/app/shared/models/widget.models.ts` (~lines 722-786: `MobileLocationResult`, new enums/interfaces, `GetLocationDescriptor`)
- Modify: `ui-ngx/src/assets/locale/locale.constant-en_US.json` (the `widget-action.mobile` object, ~line 7738-7763)

**Interfaces:**
- Produces (used by Tasks 3 and 4):
  - `MobileActionTargetEntityType` enum: `currentEntity='CURRENT_ENTITY' | currentUser='CURRENT_USER' | entityAlias='ENTITY_ALIAS' | fromAttribute='FROM_ATTRIBUTE'`
  - `MobileActionAttributeSource` enum: `currentEntity='CURRENT_ENTITY' | currentUser='CURRENT_USER'`
  - `MobileActionSaveAs` enum: `attributes='ATTRIBUTES' | timeseries='TIMESERIES'`
  - `MobileActionTargetEntityConfig { type; aliasName?; attributeSource?; attributeKey?; defaultEntityType?: EntityType }`
  - `SaveLocationDescriptor { saveToEntity?; targetEntity?; saveAs?; latitudeKey?; longitudeKey?; includeMetadata? }`
  - `GetLocationDescriptor extends SaveLocationDescriptor` (keeps `processLocationFunction`)
  - `MobileLocationResult` gains `accuracy?: number; ts?: number`
  - Translation maps: `mobileActionTargetEntityTypeTranslationMap`, `mobileActionAttributeSourceTranslationMap`, `mobileActionSaveAsTranslationMap`

- [ ] **Step 1: Extend `MobileLocationResult`**

In `ui-ngx/src/app/shared/models/widget.models.ts` replace:

```typescript
export interface MobileLocationResult {
  latitude: number;
  longitude: number;
}
```

with:

```typescript
export interface MobileLocationResult {
  latitude: number;
  longitude: number;
  accuracy?: number;
  ts?: number;
}
```

- [ ] **Step 2: Add target-entity/save enums and descriptor**

In the same file, directly above `export interface GetLocationDescriptor`, insert:

```typescript
export enum MobileActionTargetEntityType {
  currentEntity = 'CURRENT_ENTITY',
  currentUser = 'CURRENT_USER',
  entityAlias = 'ENTITY_ALIAS',
  fromAttribute = 'FROM_ATTRIBUTE'
}

export const mobileActionTargetEntityTypeTranslationMap = new Map<MobileActionTargetEntityType, string>(
  [
    [ MobileActionTargetEntityType.currentEntity, 'widget-action.mobile.target-current-entity' ],
    [ MobileActionTargetEntityType.currentUser, 'widget-action.mobile.target-current-user' ],
    [ MobileActionTargetEntityType.entityAlias, 'widget-action.mobile.target-entity-alias' ],
    [ MobileActionTargetEntityType.fromAttribute, 'widget-action.mobile.target-from-attribute' ]
  ]
);

export enum MobileActionAttributeSource {
  currentEntity = 'CURRENT_ENTITY',
  currentUser = 'CURRENT_USER'
}

export const mobileActionAttributeSourceTranslationMap = new Map<MobileActionAttributeSource, string>(
  [
    [ MobileActionAttributeSource.currentEntity, 'widget-action.mobile.target-current-entity' ],
    [ MobileActionAttributeSource.currentUser, 'widget-action.mobile.target-current-user' ]
  ]
);

export enum MobileActionSaveAs {
  attributes = 'ATTRIBUTES',
  timeseries = 'TIMESERIES'
}

export const mobileActionSaveAsTranslationMap = new Map<MobileActionSaveAs, string>(
  [
    [ MobileActionSaveAs.attributes, 'widget-action.mobile.save-as-attributes' ],
    [ MobileActionSaveAs.timeseries, 'widget-action.mobile.save-as-timeseries' ]
  ]
);

export interface MobileActionTargetEntityConfig {
  type: MobileActionTargetEntityType;
  aliasName?: string;
  attributeSource?: MobileActionAttributeSource;
  attributeKey?: string;
  defaultEntityType?: EntityType;
}

export interface SaveLocationDescriptor {
  saveToEntity?: boolean;
  targetEntity?: MobileActionTargetEntityConfig;
  saveAs?: MobileActionSaveAs;
  latitudeKey?: string;
  longitudeKey?: string;
  includeMetadata?: boolean;
}
```

and replace:

```typescript
export interface GetLocationDescriptor {
  processLocationFunction: TbFunction;
}
```

with:

```typescript
export interface GetLocationDescriptor extends SaveLocationDescriptor {
  processLocationFunction: TbFunction;
}
```

Ensure `EntityType` is imported in `widget.models.ts` (`import { EntityType } from '@shared/models/entity-type.models';`) — add to the existing import if missing.

- [ ] **Step 3: Add locale keys**

In `ui-ngx/src/assets/locale/locale.constant-en_US.json`, inside the `widget-action` → `mobile` object (after `"soft-ap": "Soft AP"` — add a trailing comma to it), insert:

```json
          "save-to-entity": "Save location to entity",
          "target-entity-type": "Target entity",
          "target-current-entity": "Current entity",
          "target-current-user": "Current user",
          "target-entity-alias": "Entity alias",
          "target-from-attribute": "From attribute value",
          "target-entity-alias-name": "Alias name",
          "target-entity-alias-name-required": "Alias name is required",
          "target-attribute-source": "Read attribute from",
          "target-attribute-key": "Attribute key",
          "target-attribute-key-required": "Attribute key is required",
          "target-default-entity-type": "Entity type of attribute value",
          "save-as": "Save as",
          "save-as-attributes": "Attributes (server scope)",
          "save-as-timeseries": "Time series",
          "latitude-key": "Latitude key",
          "longitude-key": "Longitude key",
          "include-metadata": "Also save accuracy and timestamp",
          "location-saved": "Location saved",
          "location-save-failed": "Failed to save location: {{error}}"
```

- [ ] **Step 4: Type-check**

Run: `cd /home/artem/projects/thingsboard/ui-ngx && npx tsc --noEmit -p src/tsconfig.app.json`
Expected: exits 0 (same diagnostics as before the change; no new errors). If the tsconfig path is rejected, use `yarn build` instead (slower).

- [ ] **Step 5: Commit**

```bash
cd /home/artem/projects/thingsboard
git add ui-ngx/src/app/shared/models/widget.models.ts ui-ngx/src/assets/locale/locale.constant-en_US.json
git commit -m "feat(mobile-actions): add declarative save-to-entity model for getLocation action"
```

---

### Task 3: ui-ngx — mobile action editor form + template

**Files:**
- Modify: `ui-ngx/src/app/modules/home/components/widget/lib/settings/common/action/mobile-action-editor.component.ts`
- Modify: `ui-ngx/src/app/modules/home/components/widget/lib/settings/common/action/mobile-action-editor.component.html`

**Interfaces:**
- Consumes: Task 2's enums/maps and `MobileActionTargetEntityConfig`.
- Produces: descriptor persisted from `mobileActionTypeFormGroup.getRawValue()` — flat keys `saveToEntity`, `saveAs`, `latitudeKey`, `longitudeKey`, `includeMetadata` and nested group `targetEntity` `{type, aliasName, attributeSource, attributeKey, defaultEntityType}`. Task 4 reads exactly these names off `WidgetMobileActionDescriptor`.

- [ ] **Step 1: Add imports and class fields**

In `mobile-action-editor.component.ts`, extend the `@shared/models/widget.models` import with: `MobileActionAttributeSource`, `mobileActionAttributeSourceTranslationMap`, `MobileActionSaveAs`, `mobileActionSaveAsTranslationMap`, `MobileActionTargetEntityType`, `mobileActionTargetEntityTypeTranslationMap`.

Add class fields after `provisionTypeTranslationMap` (line ~80):

```typescript
  targetEntityTypes = Object.values(MobileActionTargetEntityType);
  targetEntityTypeTranslations = mobileActionTargetEntityTypeTranslationMap;
  targetEntityType = MobileActionTargetEntityType;

  attributeSources = Object.values(MobileActionAttributeSource);
  attributeSourceTranslations = mobileActionAttributeSourceTranslationMap;

  saveAsOptions = Object.values(MobileActionSaveAs);
  saveAsTranslations = mobileActionSaveAsTranslationMap;
```

- [ ] **Step 2: Build the save-location controls in the `getLocation` case**

In `updateMobileActionType`, `case WidgetMobileActionType.getLocation:` — after the existing `addControl('processLocationFunction', ...)` call and before `break;`, insert:

```typescript
          const targetEntity = action?.targetEntity;
          this.mobileActionTypeFormGroup.addControl(
            'saveToEntity',
            this.fb.control(action?.saveToEntity || false, [])
          );
          this.mobileActionTypeFormGroup.addControl(
            'targetEntity',
            this.fb.group({
              type: [targetEntity?.type || MobileActionTargetEntityType.currentEntity, []],
              aliasName: [targetEntity?.aliasName, []],
              attributeSource: [targetEntity?.attributeSource || MobileActionAttributeSource.currentUser, []],
              attributeKey: [targetEntity?.attributeKey, []],
              defaultEntityType: [targetEntity?.defaultEntityType, []]
            })
          );
          this.mobileActionTypeFormGroup.addControl(
            'saveAs',
            this.fb.control(action?.saveAs || MobileActionSaveAs.attributes, [])
          );
          this.mobileActionTypeFormGroup.addControl(
            'latitudeKey',
            this.fb.control(action?.latitudeKey || 'latitude', [])
          );
          this.mobileActionTypeFormGroup.addControl(
            'longitudeKey',
            this.fb.control(action?.longitudeKey || 'longitude', [])
          );
          this.mobileActionTypeFormGroup.addControl(
            'includeMetadata',
            this.fb.control(action?.includeMetadata || false, [])
          );
          this.updateSaveLocationValidators();
          this.mobileActionTypeFormGroup.get('saveToEntity').valueChanges.pipe(
            takeUntilDestroyed(this.destroyRef)
          ).subscribe(() => this.updateSaveLocationValidators());
          this.mobileActionTypeFormGroup.get('targetEntity.type').valueChanges.pipe(
            takeUntilDestroyed(this.destroyRef)
          ).subscribe(() => this.updateSaveLocationValidators());
```

- [ ] **Step 3: Add the conditional validators helper**

Add as a private method after `updateMobileActionType`:

```typescript
  private updateSaveLocationValidators() {
    const saveToEntity: boolean = this.mobileActionTypeFormGroup.get('saveToEntity').value;
    const type: MobileActionTargetEntityType = this.mobileActionTypeFormGroup.get('targetEntity.type').value;
    const aliasName = this.mobileActionTypeFormGroup.get('targetEntity.aliasName');
    const attributeKey = this.mobileActionTypeFormGroup.get('targetEntity.attributeKey');
    aliasName.setValidators(
      saveToEntity && type === MobileActionTargetEntityType.entityAlias ? [Validators.required] : []);
    attributeKey.setValidators(
      saveToEntity && type === MobileActionTargetEntityType.fromAttribute ? [Validators.required] : []);
    aliasName.updateValueAndValidity({emitEvent: false});
    attributeKey.updateValueAndValidity({emitEvent: false});
  }
```

- [ ] **Step 4: Add the template block**

In `mobile-action-editor.component.html`, inside the `<ng-container [formGroup]="mobileActionTypeFormGroup">` (after the `deviceProvision` `@if` block, before the `@for (config of actionConfig ...)` loop), insert:

```html
    @if (mobileActionFormGroup.get('type').value === mobileActionType.getLocation) {
      <div class="tb-form-row">
        <mat-slide-toggle class="mat-slide" formControlName="saveToEntity">
          {{ 'widget-action.mobile.save-to-entity' | translate }}
        </mat-slide-toggle>
      </div>
      @if (mobileActionTypeFormGroup.get('saveToEntity').value) {
        <ng-container formGroupName="targetEntity">
          <div class="tb-form-row">
            <div class="fixed-title-width">{{ 'widget-action.mobile.target-entity-type' | translate }}</div>
            <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
              <mat-select formControlName="type">
                <mat-option *ngFor="let type of targetEntityTypes" [value]="type">
                  {{ targetEntityTypeTranslations.get(type) | translate }}
                </mat-option>
              </mat-select>
            </mat-form-field>
          </div>
          @if (mobileActionTypeFormGroup.get('targetEntity.type').value === targetEntityType.entityAlias) {
            <div class="tb-form-row">
              <div class="fixed-title-width">{{ 'widget-action.mobile.target-entity-alias-name' | translate }}*</div>
              <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
                <input matInput required formControlName="aliasName"
                       placeholder="{{ 'widget-action.mobile.target-entity-alias-name' | translate }}">
                <mat-icon matSuffix
                          matTooltipPosition="above"
                          matTooltipClass="tb-error-tooltip"
                          [matTooltip]="'widget-action.mobile.target-entity-alias-name-required' | translate"
                          *ngIf="mobileActionTypeFormGroup.get('targetEntity.aliasName').hasError('required')
                                 && mobileActionTypeFormGroup.get('targetEntity.aliasName').touched"
                          class="tb-error">
                  warning
                </mat-icon>
              </mat-form-field>
            </div>
          }
          @if (mobileActionTypeFormGroup.get('targetEntity.type').value === targetEntityType.fromAttribute) {
            <div class="tb-form-row">
              <div class="fixed-title-width">{{ 'widget-action.mobile.target-attribute-source' | translate }}</div>
              <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
                <mat-select formControlName="attributeSource">
                  <mat-option *ngFor="let source of attributeSources" [value]="source">
                    {{ attributeSourceTranslations.get(source) | translate }}
                  </mat-option>
                </mat-select>
              </mat-form-field>
            </div>
            <div class="tb-form-row">
              <div class="fixed-title-width">{{ 'widget-action.mobile.target-attribute-key' | translate }}*</div>
              <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
                <input matInput required formControlName="attributeKey"
                       placeholder="{{ 'widget-action.mobile.target-attribute-key' | translate }}">
                <mat-icon matSuffix
                          matTooltipPosition="above"
                          matTooltipClass="tb-error-tooltip"
                          [matTooltip]="'widget-action.mobile.target-attribute-key-required' | translate"
                          *ngIf="mobileActionTypeFormGroup.get('targetEntity.attributeKey').hasError('required')
                                 && mobileActionTypeFormGroup.get('targetEntity.attributeKey').touched"
                          class="tb-error">
                  warning
                </mat-icon>
              </mat-form-field>
            </div>
            <div class="tb-form-row">
              <div class="fixed-title-width">{{ 'widget-action.mobile.target-default-entity-type' | translate }}</div>
              <tb-entity-type-select class="flex-1" formControlName="defaultEntityType">
              </tb-entity-type-select>
            </div>
          }
        </ng-container>
        <div class="tb-form-row">
          <div class="fixed-title-width">{{ 'widget-action.mobile.save-as' | translate }}</div>
          <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
            <mat-select formControlName="saveAs">
              <mat-option *ngFor="let option of saveAsOptions" [value]="option">
                {{ saveAsTranslations.get(option) | translate }}
              </mat-option>
            </mat-select>
          </mat-form-field>
        </div>
        <div class="tb-form-row">
          <div class="fixed-title-width">{{ 'widget-action.mobile.latitude-key' | translate }}</div>
          <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
            <input matInput formControlName="latitudeKey">
          </mat-form-field>
        </div>
        <div class="tb-form-row">
          <div class="fixed-title-width">{{ 'widget-action.mobile.longitude-key' | translate }}</div>
          <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
            <input matInput formControlName="longitudeKey">
          </mat-form-field>
        </div>
        <div class="tb-form-row">
          <mat-slide-toggle class="mat-slide" formControlName="includeMetadata">
            {{ 'widget-action.mobile.include-metadata' | translate }}
          </mat-slide-toggle>
        </div>
      }
    }
```

- [ ] **Step 5: Type-check and commit**

```bash
cd /home/artem/projects/thingsboard/ui-ngx && npx tsc --noEmit -p src/tsconfig.app.json
cd /home/artem/projects/thingsboard
git add ui-ngx/src/app/modules/home/components/widget/lib/settings/common/action/
git commit -m "feat(mobile-actions): save-to-entity configuration UI for getLocation action"
```

---

### Task 4: ui-ngx — resolve target entity and save at runtime

**Files:**
- Modify: `ui-ngx/src/app/modules/home/components/widget/widget.component.ts` (`getLocation` case ~line 1371; new private methods after `handleMobileAction`'s closing brace region, ~line 1470+)

**Interfaces:**
- Consumes: Task 2's model (`mobileAction.saveToEntity`, `.targetEntity`, `.saveAs`, `.latitudeKey`, `.longitudeKey`, `.includeMetadata`; `actionResult.accuracy`, `.ts`); `this.widgetContext.aliasController` (`getEntityAliases(): EntityAliases`, `getAliasInfo(aliasId): Observable<AliasInfo>` with `currentEntity: EntityInfo {id, entityType}`); `this.widgetContext.attributeService` (`getEntityAttributes(entityId, scope, keys)`, `saveEntityAttributes(entityId, AttributeScope.SERVER_SCOPE, AttributeData[])`, `saveEntityTimeseries(entityId, 'scope', AttributeData[])` — the literal `'scope'` string matches `photo-camera-input.component.ts:261`, the path segment is ignored server-side); `getCurrentAuthUser(this.store)` from `@core/auth/auth.selectors`; `this.widgetContext.showSuccessToast/showErrorToast`; `this.translate` (already injected).
- Produces: server-side attributes/timeseries on the target entity; success/error toasts.

- [ ] **Step 1: Add imports**

In `widget.component.ts`:
- Extend the `@shared/models/widget.models` import with: `MobileActionAttributeSource`, `MobileActionSaveAs`, `MobileActionTargetEntityType`, `MobileLocationResult`.
- Add (or extend existing imports): `import { AttributeData, AttributeScope } from '@shared/models/telemetry/telemetry.models';`, `import { getCurrentAuthUser } from '@core/auth/auth.selectors';`, `EntityType` from `@shared/models/entity-type.models`, `throwError` in the `rxjs` import list, `isDefinedAndNotNull` in the `@core/utils` import list. Check each — several are likely already imported; add only what's missing.

- [ ] **Step 2: Hook the save into the `getLocation` result case**

In `handleMobileAction`, `case WidgetMobileActionType.getLocation:` (~line 1371), insert after `const longitude = actionResult.longitude;`:

```typescript
                      if (mobileAction.saveToEntity) {
                        this.saveMobileActionLocation(mobileAction, actionResult, entityId);
                      }
```

The existing `processLocationFunction` invocation stays unchanged below it (both can run).

- [ ] **Step 3: Add the resolve/save methods**

Add as private methods on `WidgetComponent` (after `handleWidgetMobileActionError`):

```typescript
  private saveMobileActionLocation(mobileAction: WidgetMobileActionDescriptor,
                                   locationResult: MobileLocationResult,
                                   currentEntityId?: EntityId): void {
    this.resolveMobileActionTargetEntity(mobileAction, currentEntityId).pipe(
      switchMap((targetEntityId) => {
        const data: Array<AttributeData> = [
          {key: mobileAction.latitudeKey || 'latitude', value: locationResult.latitude},
          {key: mobileAction.longitudeKey || 'longitude', value: locationResult.longitude}
        ];
        if (mobileAction.includeMetadata) {
          if (isDefinedAndNotNull(locationResult.accuracy)) {
            data.push({key: 'gpsAccuracy', value: locationResult.accuracy});
          }
          if (isDefinedAndNotNull(locationResult.ts)) {
            data.push({key: 'gpsTimestamp', value: locationResult.ts});
          }
        }
        if (mobileAction.saveAs === MobileActionSaveAs.timeseries) {
          return this.widgetContext.attributeService.saveEntityTimeseries(targetEntityId, 'scope', data);
        } else {
          return this.widgetContext.attributeService.saveEntityAttributes(targetEntityId, AttributeScope.SERVER_SCOPE, data);
        }
      })
    ).subscribe({
      next: () => {
        this.widgetContext.showSuccessToast(this.translate.instant('widget-action.mobile.location-saved'));
      },
      error: (err) => {
        const message = err?.message ? err.message : JSON.stringify(err);
        this.widgetContext.showErrorToast(
          this.translate.instant('widget-action.mobile.location-save-failed', {error: message}));
      }
    });
  }

  private resolveMobileActionTargetEntity(mobileAction: WidgetMobileActionDescriptor,
                                          currentEntityId?: EntityId): Observable<EntityId> {
    const target = mobileAction.targetEntity;
    const type = target?.type || MobileActionTargetEntityType.currentEntity;
    switch (type) {
      case MobileActionTargetEntityType.currentEntity:
        if (validateEntityId(currentEntityId)) {
          return of(currentEntityId);
        }
        return throwError(() => new Error('Widget action has no current entity'));
      case MobileActionTargetEntityType.currentUser:
        return of(this.currentUserEntityId());
      case MobileActionTargetEntityType.entityAlias: {
        const aliases = this.widgetContext.aliasController.getEntityAliases();
        const aliasId = Object.keys(aliases).find(id => aliases[id].alias === target.aliasName);
        if (!aliasId) {
          return throwError(() => new Error(`Entity alias '${target.aliasName}' not found in the dashboard`));
        }
        return this.widgetContext.aliasController.getAliasInfo(aliasId).pipe(
          map((aliasInfo) => {
            const entity = aliasInfo.currentEntity;
            if (!entity?.id || !entity?.entityType) {
              throw new Error(`Entity alias '${target.aliasName}' did not resolve to an entity`);
            }
            return {entityType: entity.entityType, id: entity.id} as EntityId;
          })
        );
      }
      case MobileActionTargetEntityType.fromAttribute: {
        let sourceEntityId: EntityId;
        if (target.attributeSource === MobileActionAttributeSource.currentEntity) {
          if (!validateEntityId(currentEntityId)) {
            return throwError(() => new Error('Widget action has no current entity'));
          }
          sourceEntityId = currentEntityId;
        } else {
          sourceEntityId = this.currentUserEntityId();
        }
        return this.widgetContext.attributeService.getEntityAttributes(
          sourceEntityId, AttributeScope.SERVER_SCOPE, [target.attributeKey]).pipe(
          map((attributes) => {
            const attribute = attributes.find(a => a.key === target.attributeKey);
            if (!attribute || !isDefinedAndNotNull(attribute.value)) {
              throw new Error(`Attribute '${target.attributeKey}' not found on the source entity`);
            }
            return this.parseTargetEntityAttributeValue(attribute.value, target.defaultEntityType);
          })
        );
      }
    }
  }

  private currentUserEntityId(): EntityId {
    const authUser = getCurrentAuthUser(this.store);
    return {entityType: EntityType.USER, id: authUser.userId};
  }

  private parseTargetEntityAttributeValue(value: any, defaultEntityType?: EntityType): EntityId {
    if (typeof value === 'object' && value?.id && value?.entityType) {
      return {entityType: value.entityType, id: value.id};
    }
    if (typeof value === 'string') {
      let parsed: any = null;
      try {
        parsed = JSON.parse(value);
      } catch (e) {}
      if (parsed?.id && parsed?.entityType) {
        return {entityType: parsed.entityType, id: parsed.id};
      }
      if (defaultEntityType) {
        return {entityType: defaultEntityType, id: value};
      }
    }
    throw new Error('Attribute value does not identify a target entity ' +
      '(expected {entityType, id} JSON or a UUID with a configured entity type)');
  }
```

- [ ] **Step 4: Type-check and commit**

```bash
cd /home/artem/projects/thingsboard/ui-ngx && npx tsc --noEmit -p src/tsconfig.app.json
cd /home/artem/projects/thingsboard
git add ui-ngx/src/app/modules/home/components/widget/widget.component.ts
git commit -m "feat(mobile-actions): resolve target entity and save phone location on getLocation result"
```

---

### Task 5: End-to-end smoke test (manual, real device)

**Files:** none (verification only).

- [ ] **Step 1: Run the stack**

- Backend: local ThingsBoard CE (user's existing dev setup).
- Frontend: `cd /home/artem/projects/thingsboard/ui-ngx && yarn start` (proxies to the local backend).
- Mobile: `flutter run` (debug) on the Android device, endpoint pointed at the same server (must be reachable from the phone — use the machine's LAN IP).

- [ ] **Step 2: Configure the action**

On a dashboard, add any widget with actions (e.g. a button/table), add an action → type **Mobile action** → **Get phone location**. Enable **Save location to entity**, target **Current user**, keys default, **Save as: Attributes**, enable metadata toggle.

- [ ] **Step 3: Verify each target mode**

1. **Current user**: trigger the action from the phone's dashboard view → expect success toast in the WebView and `latitude`/`longitude`/`gpsAccuracy`/`gpsTimestamp` server attributes on your user (check via ui-ngx or the phone).
2. **Entity alias**: create a single-entity alias (e.g. a test device) on the dashboard, switch target to alias + its name → trigger → attributes land on the device.
3. **From attribute**: on your user, create server attribute `trackedEntityId` = `{"entityType":"DEVICE","id":"<uuid>"}` → switch target to From attribute / Current user / `trackedEntityId` → trigger → attributes land on that device.
4. **Timeseries mode**: switch Save as to Time series → trigger → values appear as latest telemetry.
5. **Backward compat**: create a plain Get phone location action without the save toggle → behaves exactly as before (dialog from `processLocationFunction` default).
6. **Web browser (non-mobile)**: trigger from desktop browser → `handleNonMobileFallbackFunction` path unchanged (no save attempted, no errors in console).

- [ ] **Step 4: Record results**

Note any deviations; fix-forward small issues in the relevant task's files and amend/commit with `fix:` prefix.
