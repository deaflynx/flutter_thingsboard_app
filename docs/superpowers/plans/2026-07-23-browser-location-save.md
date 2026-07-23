# Browser-side Location Save (widget action) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new generic `saveBrowserLocation` widget action that reads the browser's current geolocation once on trigger and saves the coordinates (plus optional browser metrics) to a resolvable target entity.

**Architecture:** A new `WidgetActionType.saveBrowserLocation` handled in `WidgetComponent`'s action switch. It reuses the existing mobile-action target-entity model (`MobileActionTargetEntityConfig` + `MobileActionSaveAs`) and the existing save path (`AttributeService`). A new small `BrowserGeolocationService` wraps `navigator.geolocation` (greenfield — nothing like it exists). A new editor component mirrors the mobile-action editor's target-entity sub-form. Web-only: no backend, no mobile-app, no map involvement.

**Tech Stack:** Angular 18 (ui-ngx), RxJS, Angular reactive forms + ControlValueAccessor, `@ngx-translate`.

## Global Constraints

- Repo: `thingsboard` at `/home/artem/projects/thingsboard`, branch `feat/gps-tracker` (the branch that already carries the phase-1d bundle-page change). All work is under `ui-ngx/`. Leave the pre-existing uncommitted `ui-ngx/proxy.conf.js` change alone.
- Conventional Commits; **no** `Co-Authored-By` lines.
- Verification per task (repo convention — **no test scaffolding in ui-ngx**): `cd /home/artem/projects/thingsboard/ui-ngx && npx tsc --noEmit -p src/tsconfig.app.json` must exit 0 (only any pre-existing photoswipe errors are acceptable).
- User-facing strings are localized in `ui-ngx/src/assets/locale/locale.constant-en_US.json` only (other locales fall back to English).
- Reuse existing enums/translations rather than duplicating: `MobileActionTargetEntityType`, `MobileActionAttributeSource`, `MobileActionSaveAs`, and their `*TranslationMap`s.
- The wire/type string is exactly `saveBrowserLocation` (enum member name === value).
- Spec: `docs/superpowers/specs/2026-07-23-browser-location-save-design.md` (in the flutter repo, alongside the other GPS specs).

---

### Task 1: Model — enum member, descriptor interface, config field, translation

**Files:**
- Modify: `ui-ngx/src/app/shared/models/widget.models.ts` (enum ~L611-621; `widgetActionTypeTranslationMap` ~L672-684; `WidgetAction` ~L887-911; add the new interface near the mobile save-location descriptors ~L824-862)

**Interfaces:**
- Consumes: `MobileActionTargetEntityConfig` (`widget.models.ts:816-822`), `MobileActionSaveAs` (`:804-807`).
- Produces: `WidgetActionType.saveBrowserLocation`; `SaveBrowserLocationDescriptor`; `WidgetAction.saveBrowserLocation?: SaveBrowserLocationDescriptor`. Consumed by Tasks 3 (dispatch) and 5 (editor).

- [ ] **Step 1: Add the enum member**

In `widget.models.ts`, add `saveBrowserLocation` to `WidgetActionType` (after `placeMapItem`):

```ts
export enum WidgetActionType {
  doNothing = 'doNothing',
  openDashboardState = 'openDashboardState',
  updateDashboardState = 'updateDashboardState',
  openDashboard = 'openDashboard',
  custom = 'custom',
  customPretty = 'customPretty',
  mobileAction = 'mobileAction',
  openURL = 'openURL',
  placeMapItem = 'placeMapItem',
  saveBrowserLocation = 'saveBrowserLocation'
}
```

(`saveBrowserLocation` is NOT filtered out of `widgetActionTypes` — unlike `placeMapItem` — so it becomes user-selectable automatically.)

- [ ] **Step 2: Add the translation-map entry**

Add to `widgetActionTypeTranslationMap` (after the `placeMapItem` entry):

```ts
    [ WidgetActionType.placeMapItem, 'widget-action.place-map-item' ],
    [ WidgetActionType.saveBrowserLocation, 'widget-action.save-browser-location' ],
```

- [ ] **Step 3: Add the descriptor interface**

Add near the existing `SaveLocationDescriptor`/`StartLiveLocationDescriptor` block (~L824-862):

```ts
export interface SaveBrowserLocationDescriptor {
  targetEntity?: MobileActionTargetEntityConfig;
  saveAs?: MobileActionSaveAs;
  latitudeKey?: string;
  longitudeKey?: string;
  accuracyKey?: string;
  altitudeKey?: string;
  altitudeAccuracyKey?: string;
  headingKey?: string;
  speedKey?: string;
  timestampKey?: string;
}
```

- [ ] **Step 4: Add the config field to `WidgetAction`**

In `interface WidgetAction` (near `mobileAction?`/`mapItemType?`, ~L908-911), add:

```ts
  mobileAction?: WidgetMobileActionDescriptor;
  url?: string;
  mapItemType?: MapItemType;
  mapItemTooltips?: MapItemTooltips;
  saveBrowserLocation?: SaveBrowserLocationDescriptor;
```

- [ ] **Step 5: Verify + commit**

```bash
cd /home/artem/projects/thingsboard/ui-ngx && npx tsc --noEmit -p src/tsconfig.app.json ; echo "exit: $?"
```
Expected: exit 0 (only any pre-existing photoswipe errors).

```bash
cd /home/artem/projects/thingsboard
git add ui-ngx/src/app/shared/models/widget.models.ts
git commit -m "feat(widget): add saveBrowserLocation widget action type and descriptor"
```

---

### Task 2: i18n keys

**Files:**
- Modify: `ui-ngx/src/assets/locale/locale.constant-en_US.json` (the `"widget-action"` block starts at L7685; its nested `"mobile"` object closes at ~L7796)

**Interfaces:**
- Produces: translation keys `widget-action.save-browser-location` (the type label) and the `widget-action.browser-location.*` object (toasts, geolocation errors, optional-key labels). Consumed by Tasks 3 and 5. The service in Task 3 hard-codes the `widget-action.browser-location.error-*` keys, so the names must match exactly.

- [ ] **Step 1: Add the type label + the `browser-location` sub-object**

Inside the top-level `"widget-action"` object (a good spot is immediately after the `"mobile": { ... }` object closes at ~L7796), add the type label and a sibling namespace object. Match the file's 2-space-incremental indentation and trailing-comma style:

```json
          "save-browser-location": "Save browser location",
          "browser-location": {
            "location-saved": "Browser location saved",
            "location-save-failed": "Failed to save browser location: {{error}}",
            "error-insecure-context": "Browser location requires a secure (HTTPS) connection",
            "error-permission-denied": "Location permission was denied",
            "error-position-unavailable": "Current location is unavailable",
            "error-timeout": "Timed out while getting the current location",
            "optional-key-hint": "Leave blank to skip saving this value",
            "accuracy-key": "Accuracy key",
            "altitude-key": "Altitude key",
            "altitude-accuracy-key": "Altitude accuracy key",
            "heading-key": "Heading key",
            "speed-key": "Speed key",
            "timestamp-key": "Timestamp key"
          },
```

(The editor in Task 5 reuses the existing `widget-action.mobile.*` labels for target-entity/save-as/latitude/longitude, so those are not re-added here.)

- [ ] **Step 2: Verify the JSON is well-formed + commit**

```bash
cd /home/artem/projects/thingsboard/ui-ngx && node -e "JSON.parse(require('fs').readFileSync('src/assets/locale/locale.constant-en_US.json','utf8')); console.log('valid json')"
```
Expected: `valid json`.

```bash
cd /home/artem/projects/thingsboard
git add ui-ngx/src/assets/locale/locale.constant-en_US.json
git commit -m "feat(widget): add i18n for saveBrowserLocation action"
```

---

### Task 3: Browser geolocation service

**Files:**
- Create: `ui-ngx/src/app/core/services/browser-geolocation.service.ts`

**Interfaces:**
- Produces: `BrowserGeolocationService.getCurrentPosition(): Observable<GeolocationPosition>` (root-provided); `BrowserGeolocationError` (carries a `BrowserGeolocationErrorType`); `browserGeolocationErrorMessageKey(error): string` (pure — maps to a `widget-action.browser-location.error-*` i18n key). Consumed by Task 4.

- [ ] **Step 1: Create the service**

Create `ui-ngx/src/app/core/services/browser-geolocation.service.ts`:

```ts
///
/// Copyright © 2016-2025 The Thingsboard Authors
///
/// Licensed under the Apache License, Version 2.0 (the "License");
/// you may not use this file except in compliance with the License.
/// You may obtain a copy of the License at
///
///     http://www.apache.org/licenses/LICENSE-2.0
///
/// Unless required by applicable law or agreed to in writing, software
/// distributed under the License is distributed on an "AS IS" BASIS,
/// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
/// See the License for the specific language governing permissions and
/// limitations under the License.
///

import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

export enum BrowserGeolocationErrorType {
  insecureContext = 'insecureContext',
  permissionDenied = 'permissionDenied',
  positionUnavailable = 'positionUnavailable',
  timeout = 'timeout'
}

export class BrowserGeolocationError extends Error {
  constructor(public readonly errorType: BrowserGeolocationErrorType) {
    super(errorType);
  }
}

const browserGeolocationErrorMessageKeys: {[key in BrowserGeolocationErrorType]: string} = {
  [BrowserGeolocationErrorType.insecureContext]: 'widget-action.browser-location.error-insecure-context',
  [BrowserGeolocationErrorType.permissionDenied]: 'widget-action.browser-location.error-permission-denied',
  [BrowserGeolocationErrorType.positionUnavailable]: 'widget-action.browser-location.error-position-unavailable',
  [BrowserGeolocationErrorType.timeout]: 'widget-action.browser-location.error-timeout'
};

export function browserGeolocationErrorMessageKey(error: unknown): string {
  const errorType = error instanceof BrowserGeolocationError
    ? error.errorType
    : BrowserGeolocationErrorType.positionUnavailable;
  return browserGeolocationErrorMessageKeys[errorType];
}

function toBrowserGeolocationError(error: GeolocationPositionError): BrowserGeolocationError {
  switch (error.code) {
    case error.PERMISSION_DENIED:
      return new BrowserGeolocationError(BrowserGeolocationErrorType.permissionDenied);
    case error.TIMEOUT:
      return new BrowserGeolocationError(BrowserGeolocationErrorType.timeout);
    default:
      return new BrowserGeolocationError(BrowserGeolocationErrorType.positionUnavailable);
  }
}

@Injectable({
  providedIn: 'root'
})
export class BrowserGeolocationService {

  getCurrentPosition(): Observable<GeolocationPosition> {
    return new Observable<GeolocationPosition>((subscriber) => {
      if (!window.isSecureContext || !navigator.geolocation) {
        subscriber.error(new BrowserGeolocationError(BrowserGeolocationErrorType.insecureContext));
        return;
      }
      navigator.geolocation.getCurrentPosition(
        (position) => {
          subscriber.next(position);
          subscriber.complete();
        },
        (error) => subscriber.error(toBrowserGeolocationError(error)),
        { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 }
      );
    });
  }
}
```

- [ ] **Step 2: Verify + commit**

```bash
cd /home/artem/projects/thingsboard/ui-ngx && npx tsc --noEmit -p src/tsconfig.app.json ; echo "exit: $?"
```
Expected: exit 0.

```bash
cd /home/artem/projects/thingsboard
git add ui-ngx/src/app/core/services/browser-geolocation.service.ts
git commit -m "feat(widget): add browser geolocation service"
```

---

### Task 4: Dispatch handler in WidgetComponent

**Files:**
- Modify: `ui-ngx/src/app/modules/home/components/widget/widget.component.ts` (imports; constructor ~L227; action switch ~L1214-1228; resolver ~L1573; add the new handler)

**Interfaces:**
- Consumes: `BrowserGeolocationService`/`BrowserGeolocationError`/`browserGeolocationErrorMessageKey` (Task 3), `SaveBrowserLocationDescriptor`/`MobileActionSaveAs`/`MobileActionTargetEntityConfig` (Task 1), `AttributeService` (via `widgetContext`), `LatestTelemetry`/`AttributeScope`/`AttributeData`.
- Produces: runtime handling of `WidgetActionType.saveBrowserLocation`. The existing `resolveMobileActionTargetEntity` is refactored to delegate to a new generic `resolveActionTargetEntity(target, currentEntityId)` — behavior for the mobile action is unchanged.

- [ ] **Step 1: Add imports**

Add the new service import (group with other `@core` service imports):

```ts
import { BrowserGeolocationError, browserGeolocationErrorMessageKey, BrowserGeolocationService } from '@core/services/browser-geolocation.service';
```

Add `SaveBrowserLocationDescriptor` and `MobileActionTargetEntityConfig` to the existing import from `@shared/models/widget.models` (both live there; `MobileActionSaveAs` is already imported and used at L1531). Add `LatestTelemetry` to the existing import from `@shared/models/telemetry/telemetry.models` (`AttributeScope`, `AttributeData` are already imported/used at L1519/L1534).

- [ ] **Step 2: Inject the service in the constructor**

In the `WidgetComponent` constructor parameter list (near `private translate: TranslateService,` at L227), add:

```ts
              private translate: TranslateService,
              private browserGeolocationService: BrowserGeolocationService,
```

- [ ] **Step 3: Add the dispatch case**

In the action-type `switch` (the block ending at L1228), add a case after `mobileAction` and before the closing brace:

```ts
      case WidgetActionType.mobileAction:
        const mobileAction = descriptor.mobileAction;
        this.handleMobileAction($event, mobileAction, entityId, entityName, additionalParams, entityLabel);
        break;
      case WidgetActionType.saveBrowserLocation:
        this.saveBrowserLocation(descriptor, entityId);
        break;
    }
```

- [ ] **Step 4: Refactor the target resolver to be generic (behavior-preserving)**

Replace the header of `resolveMobileActionTargetEntity` (L1573) so it delegates to a new generic method, and rename the body's method to `resolveActionTargetEntity` taking the config directly. Concretely: keep everything from `const target = mobileAction.targetEntity;` onward, but move it into a new method whose parameter IS `target`, and make the old method a one-line delegator. The result:

```ts
  private resolveMobileActionTargetEntity(mobileAction: WidgetMobileActionDescriptor,
                                          currentEntityId?: EntityId): Observable<EntityId> {
    return this.resolveActionTargetEntity(mobileAction.targetEntity, currentEntityId);
  }

  private resolveActionTargetEntity(target: MobileActionTargetEntityConfig,
                                    currentEntityId?: EntityId): Observable<EntityId> {
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
        const aliasId = this.widgetContext.aliasController.getEntityAliasId(target.aliasName);
        if (!aliasId) {
          return throwError(() => new Error(`Entity alias '${target.aliasName}' not found in the dashboard`));
        }
        return this.widgetContext.aliasController.resolveSingleEntityInfo(aliasId).pipe(
          map((entity) => {
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
          sourceEntityId, AttributeScope.SERVER_SCOPE, [target.attributeKey], {ignoreErrors: true}).pipe(
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
```

(This is the original body verbatim, only the entry point changed. `currentUserEntityId` and `parseTargetEntityAttributeValue` are unchanged.)

- [ ] **Step 5: Add the `saveBrowserLocation` handler**

Add this method (mirrors the existing `saveMobileActionLocation` at L1514, which is the same resolve→save→toast shape). Place it near `saveMobileActionLocation`:

```ts
  private saveBrowserLocation(descriptor: WidgetActionDescriptor, currentEntityId?: EntityId): void {
    const config = descriptor.saveBrowserLocation;
    if (!config) {
      return;
    }
    defer(() => this.browserGeolocationService.getCurrentPosition()).pipe(
      switchMap((position) => this.resolveActionTargetEntity(config.targetEntity, currentEntityId).pipe(
        switchMap((targetEntityId) => {
          const coords = position.coords;
          const data: Array<AttributeData> = [];
          const addValue = (key: string | undefined, value: number | null | undefined) => {
            const trimmed = (key || '').trim();
            if (trimmed.length && isDefinedAndNotNull(value) && !Number.isNaN(value)) {
              data.push({key: trimmed, value});
            }
          };
          addValue(config.latitudeKey || 'latitude', coords.latitude);
          addValue(config.longitudeKey || 'longitude', coords.longitude);
          addValue(config.accuracyKey, coords.accuracy);
          addValue(config.altitudeKey, coords.altitude);
          addValue(config.altitudeAccuracyKey, coords.altitudeAccuracy);
          addValue(config.headingKey, coords.heading);
          addValue(config.speedKey, coords.speed);
          addValue(config.timestampKey, position.timestamp);
          if (!data.length) {
            return of(null);
          }
          if (config.saveAs === MobileActionSaveAs.timeseries) {
            return this.widgetContext.attributeService.saveEntityTimeseries(
              targetEntityId, LatestTelemetry.LATEST_TELEMETRY, data, {ignoreErrors: true});
          }
          return this.widgetContext.attributeService.saveEntityAttributes(
            targetEntityId, AttributeScope.SERVER_SCOPE, data, {ignoreErrors: true});
        })
      ))
    ).subscribe({
      next: () => {
        this.widgetContext.showSuccessToast(
          this.translate.instant('widget-action.browser-location.location-saved'));
      },
      error: (err) => {
        if (err instanceof BrowserGeolocationError) {
          this.widgetContext.showErrorToast(this.translate.instant(browserGeolocationErrorMessageKey(err)));
        } else {
          const message = err?.error?.message || err?.message || JSON.stringify(err);
          this.widgetContext.showErrorToast(
            this.translate.instant('widget-action.browser-location.location-save-failed', {error: message}));
        }
      }
    });
  }
```

(Note: uses `LatestTelemetry.LATEST_TELEMETRY` for the timeseries scope — the correct value per `TbMap.saveItemData` — rather than the literal `'scope'` seen in the older `saveMobileActionLocation`. `defer`, `switchMap`, `of` are already imported in this file.)

- [ ] **Step 6: Verify + commit**

```bash
cd /home/artem/projects/thingsboard/ui-ngx && npx tsc --noEmit -p src/tsconfig.app.json ; echo "exit: $?"
```
Expected: exit 0.

```bash
cd /home/artem/projects/thingsboard
git add ui-ngx/src/app/modules/home/components/widget/widget.component.ts
git commit -m "feat(widget): handle saveBrowserLocation action at runtime"
```

---

### Task 5: Action config editor + wiring

**Files:**
- Create: `ui-ngx/src/app/modules/home/components/widget/lib/settings/common/action/save-browser-location-action-editor.component.ts`
- Create: `ui-ngx/src/app/modules/home/components/widget/lib/settings/common/action/save-browser-location-action-editor.component.html`
- Modify: `ui-ngx/src/app/modules/home/components/widget/lib/settings/common/widget-settings-common.module.ts` (import + declarations ~L304-310 + exports ~L416-419)
- Modify: `ui-ngx/src/app/modules/home/components/widget/lib/settings/common/action/widget-action.component.ts` (`updateActionTypeFormGroup` ~L244-348)
- Modify: `ui-ngx/src/app/modules/home/components/widget/lib/settings/common/action/widget-action.component.html` (the `ngSwitch` ~L286-289)

**Interfaces:**
- Consumes: `SaveBrowserLocationDescriptor` (Task 1); `MobileActionTargetEntityType`/`MobileActionAttributeSource`/`MobileActionSaveAs` + their `*TranslationMap`s; `WidgetActionCallbacks` (for `fetchEntityAliases`).
- Produces: the `tb-save-browser-location-action-editor` component; the `saveBrowserLocation` control wired into `WidgetActionComponent`. The generic branch of `widgetActionUpdated` (`{...widgetActionFormGroup.value, ...actionTypeFormGroup.value}`) nests the value under `saveBrowserLocation`, matching Task 1's `WidgetAction.saveBrowserLocation`.

- [ ] **Step 1: Create the editor component `.ts`**

Create `save-browser-location-action-editor.component.ts`:

```ts
///
/// Copyright © 2016-2025 The Thingsboard Authors
///
/// Licensed under the Apache License, Version 2.0 (the "License");
/// you may not use this file except in compliance with the License.
/// You may obtain a copy of the License at
///
///     http://www.apache.org/licenses/LICENSE-2.0
///
/// Unless required by applicable law or agreed to in writing, software
/// distributed under the License is distributed on an "AS IS" BASIS,
/// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
/// See the License for the specific language governing permissions and
/// limitations under the License.
///

import { Component, forwardRef, Input, OnDestroy, OnInit } from '@angular/core';
import {
  ControlValueAccessor,
  NG_VALUE_ACCESSOR,
  UntypedFormBuilder,
  UntypedFormGroup,
  Validators
} from '@angular/forms';
import {
  MobileActionAttributeSource,
  mobileActionAttributeSourceTranslationMap,
  MobileActionSaveAs,
  mobileActionSaveAsTranslationMap,
  MobileActionTargetEntityType,
  mobileActionTargetEntityTypeTranslationMap,
  SaveBrowserLocationDescriptor,
  WidgetActionCallbacks
} from '@shared/models/widget.models';
import { Observable, Subject } from 'rxjs';
import { map, startWith, takeUntil } from 'rxjs/operators';

@Component({
  selector: 'tb-save-browser-location-action-editor',
  templateUrl: './save-browser-location-action-editor.component.html',
  styleUrls: [],
  providers: [
    {
      provide: NG_VALUE_ACCESSOR,
      useExisting: forwardRef(() => SaveBrowserLocationActionEditorComponent),
      multi: true
    }
  ],
  standalone: false
})
export class SaveBrowserLocationActionEditorComponent implements ControlValueAccessor, OnInit, OnDestroy {

  @Input()
  disabled: boolean;

  @Input()
  callbacks: WidgetActionCallbacks;

  formGroup: UntypedFormGroup;

  targetEntityTypes = Object.values(MobileActionTargetEntityType);
  targetEntityType = MobileActionTargetEntityType;
  targetEntityTypeTranslations = mobileActionTargetEntityTypeTranslationMap;
  attributeSources = Object.values(MobileActionAttributeSource);
  attributeSourceTranslations = mobileActionAttributeSourceTranslationMap;
  saveAsOptions = Object.values(MobileActionSaveAs);
  saveAsTranslations = mobileActionSaveAsTranslationMap;

  entityAliasNames: string[] = [];
  filteredEntityAliasNames: Observable<string[]>;

  private destroy$ = new Subject<void>();
  private propagateChange = (_val: any) => {};

  constructor(private fb: UntypedFormBuilder) {}

  ngOnInit(): void {
    this.formGroup = this.fb.group({
      targetEntity: this.fb.group({
        type: [MobileActionTargetEntityType.currentEntity, []],
        aliasName: [null, []],
        attributeSource: [MobileActionAttributeSource.currentUser, []],
        attributeKey: [null, []],
        defaultEntityType: [null, []]
      }),
      saveAs: [MobileActionSaveAs.attributes, []],
      latitudeKey: ['latitude', [Validators.required]],
      longitudeKey: ['longitude', [Validators.required]],
      accuracyKey: ['', []],
      altitudeKey: ['', []],
      altitudeAccuracyKey: ['', []],
      headingKey: ['', []],
      speedKey: ['', []],
      timestampKey: ['', []]
    });

    this.entityAliasNames = (this.callbacks?.fetchEntityAliases?.() ?? []).map((alias) => alias.alias);
    const aliasNameControl = this.formGroup.get('targetEntity.aliasName');
    this.filteredEntityAliasNames = aliasNameControl.valueChanges.pipe(
      startWith(aliasNameControl.value ?? ''),
      map((value: string) => (value ?? '').toLowerCase()),
      map((search) => this.entityAliasNames.filter((name) => name.toLowerCase().includes(search)))
    );

    this.formGroup.get('targetEntity.type').valueChanges.pipe(
      takeUntil(this.destroy$)
    ).subscribe(() => this.updateTargetEntityValidators());

    this.formGroup.valueChanges.pipe(
      takeUntil(this.destroy$)
    ).subscribe(() => this.propagateChange(this.formGroup.getRawValue()));

    this.updateTargetEntityValidators();
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
  }

  registerOnChange(fn: any): void {
    this.propagateChange = fn;
  }

  registerOnTouched(_fn: any): void {}

  setDisabledState(isDisabled: boolean): void {
    this.disabled = isDisabled;
    if (isDisabled) {
      this.formGroup.disable({emitEvent: false});
    } else {
      this.formGroup.enable({emitEvent: false});
      this.updateTargetEntityValidators();
    }
  }

  writeValue(value?: SaveBrowserLocationDescriptor): void {
    this.formGroup.patchValue({
      targetEntity: {
        type: value?.targetEntity?.type || MobileActionTargetEntityType.currentEntity,
        aliasName: value?.targetEntity?.aliasName ?? null,
        attributeSource: value?.targetEntity?.attributeSource || MobileActionAttributeSource.currentUser,
        attributeKey: value?.targetEntity?.attributeKey ?? null,
        defaultEntityType: value?.targetEntity?.defaultEntityType ?? null
      },
      saveAs: value?.saveAs || MobileActionSaveAs.attributes,
      latitudeKey: value?.latitudeKey || 'latitude',
      longitudeKey: value?.longitudeKey || 'longitude',
      accuracyKey: value?.accuracyKey ?? '',
      altitudeKey: value?.altitudeKey ?? '',
      altitudeAccuracyKey: value?.altitudeAccuracyKey ?? '',
      headingKey: value?.headingKey ?? '',
      speedKey: value?.speedKey ?? '',
      timestampKey: value?.timestampKey ?? ''
    }, {emitEvent: false});
    this.updateTargetEntityValidators();
  }

  private updateTargetEntityValidators(): void {
    const type: MobileActionTargetEntityType = this.formGroup.get('targetEntity.type').value;
    const aliasName = this.formGroup.get('targetEntity.aliasName');
    const attributeKey = this.formGroup.get('targetEntity.attributeKey');
    aliasName.setValidators(type === MobileActionTargetEntityType.entityAlias ? [Validators.required] : []);
    attributeKey.setValidators(type === MobileActionTargetEntityType.fromAttribute ? [Validators.required] : []);
    aliasName.updateValueAndValidity({emitEvent: false});
    attributeKey.updateValueAndValidity({emitEvent: false});
  }
}
```

- [ ] **Step 2: Create the editor `.html`**

Create `save-browser-location-action-editor.component.html`. The target-entity block mirrors `mobile-action-editor.component.html`'s `#targetEntityConfig` (reusing its i18n keys):

```html
<div [formGroup]="formGroup">
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
    @if (formGroup.get('targetEntity.type').value === targetEntityType.entityAlias) {
      <div class="tb-form-row">
        <div class="fixed-title-width">{{ 'widget-action.mobile.target-entity-alias-name' | translate }}*</div>
        <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
          <input matInput required formControlName="aliasName"
                 [matAutocomplete]="entityAliasNameAutocomplete"
                 placeholder="{{ 'widget-action.mobile.target-entity-alias-name' | translate }}">
          <mat-autocomplete #entityAliasNameAutocomplete="matAutocomplete" class="tb-autocomplete">
            <mat-option *ngFor="let name of filteredEntityAliasNames | async" [value]="name">
              {{ name }}
            </mat-option>
          </mat-autocomplete>
        </mat-form-field>
      </div>
    }
    @if (formGroup.get('targetEntity.type').value === targetEntityType.fromAttribute) {
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
        </mat-form-field>
      </div>
      <div class="tb-form-row">
        <div class="fixed-title-width">{{ 'widget-action.mobile.target-default-entity-type' | translate }}</div>
        <tb-entity-type-select class="flex-1" appearance="outline" formControlName="defaultEntityType">
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

  <div class="tb-hint">{{ 'widget-action.browser-location.optional-key-hint' | translate }}</div>
  <div class="tb-form-row">
    <div class="fixed-title-width">{{ 'widget-action.browser-location.accuracy-key' | translate }}</div>
    <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
      <input matInput formControlName="accuracyKey">
    </mat-form-field>
  </div>
  <div class="tb-form-row">
    <div class="fixed-title-width">{{ 'widget-action.browser-location.altitude-key' | translate }}</div>
    <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
      <input matInput formControlName="altitudeKey">
    </mat-form-field>
  </div>
  <div class="tb-form-row">
    <div class="fixed-title-width">{{ 'widget-action.browser-location.altitude-accuracy-key' | translate }}</div>
    <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
      <input matInput formControlName="altitudeAccuracyKey">
    </mat-form-field>
  </div>
  <div class="tb-form-row">
    <div class="fixed-title-width">{{ 'widget-action.browser-location.heading-key' | translate }}</div>
    <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
      <input matInput formControlName="headingKey">
    </mat-form-field>
  </div>
  <div class="tb-form-row">
    <div class="fixed-title-width">{{ 'widget-action.browser-location.speed-key' | translate }}</div>
    <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
      <input matInput formControlName="speedKey">
    </mat-form-field>
  </div>
  <div class="tb-form-row">
    <div class="fixed-title-width">{{ 'widget-action.browser-location.timestamp-key' | translate }}</div>
    <mat-form-field class="flex-1" appearance="outline" subscriptSizing="dynamic">
      <input matInput formControlName="timestampKey">
    </mat-form-field>
  </div>
</div>
```

- [ ] **Step 3: Register the component in the module**

In `widget-settings-common.module.ts`:

Add the import (near the other action editor imports ~L71-82):

```ts
import { SaveBrowserLocationActionEditorComponent } from '@home/components/widget/lib/settings/common/action/save-browser-location-action-editor.component';
```

Add to the `declarations` array (near `MobileActionEditorComponent` at ~L308):

```ts
    MobileActionEditorComponent,
    SaveBrowserLocationActionEditorComponent,
```

Add to the `exports` array (near `MobileActionEditorComponent` at ~L419):

```ts
    MobileActionEditorComponent,
    SaveBrowserLocationActionEditorComponent,
```

- [ ] **Step 4: Add the form control in `WidgetActionComponent`**

In `widget-action.component.ts`, in `updateActionTypeFormGroup(...)`, add a case alongside `mobileAction` (~L312-317):

```ts
      case WidgetActionType.saveBrowserLocation:
        this.actionTypeFormGroup.addControl(
          'saveBrowserLocation',
          this.fb.control(action ? action.saveBrowserLocation : null, [Validators.required])
        );
        break;
```

(The generic branch of `widgetActionUpdated` already spreads `actionTypeFormGroup.value`, so the control's value is emitted under the `saveBrowserLocation` key — no change needed there.)

- [ ] **Step 5: Render the editor in `widget-action.component.html`**

Add a `ngSwitchCase` alongside the `mobileAction` one (~L286-289):

```html
    <ng-template [ngSwitchCase]="widgetActionType.saveBrowserLocation">
      <tb-save-browser-location-action-editor [callbacks]="callbacks" formControlName="saveBrowserLocation">
      </tb-save-browser-location-action-editor>
    </ng-template>
```

- [ ] **Step 6: Verify + commit**

```bash
cd /home/artem/projects/thingsboard/ui-ngx && npx tsc --noEmit -p src/tsconfig.app.json ; echo "exit: $?"
```
Expected: exit 0.

```bash
cd /home/artem/projects/thingsboard
git add ui-ngx/src/app/modules/home/components/widget/lib/settings/common/action/save-browser-location-action-editor.component.ts \
        ui-ngx/src/app/modules/home/components/widget/lib/settings/common/action/save-browser-location-action-editor.component.html \
        ui-ngx/src/app/modules/home/components/widget/lib/settings/common/widget-settings-common.module.ts \
        ui-ngx/src/app/modules/home/components/widget/lib/settings/common/action/widget-action.component.ts \
        ui-ngx/src/app/modules/home/components/widget/lib/settings/common/action/widget-action.component.html
git commit -m "feat(widget): add saveBrowserLocation action config editor"
```

---

### Task 6: Manual smoke test (verification only)

**Files:** none.

- [ ] **Step 1** — `yarn start` ui-ngx over HTTPS (or a secure-context dev setup). On a dashboard widget, add a widget action; confirm **"Save browser location"** appears in the action-type dropdown.
- [ ] **Step 2** — Configure it: target **Current entity**, saveAs **Attributes**, keep latitude/longitude, set `accuracy` key. Trigger the action → browser prompts for location → on allow, a success toast appears and the entity gains `latitude`/`longitude`/`accuracy` server-scope attributes.
- [ ] **Step 3** — Set saveAs **Time series** → values land as latest telemetry instead.
- [ ] **Step 4** — Target **Entity alias** and **From attribute** → saves to the resolved entity; a bad alias/attribute shows the save-failed error toast.
- [ ] **Step 5** — Deny the permission prompt → permission-denied toast. Load the dashboard over plain HTTP → insecure-context toast (no crash).
- [ ] **Step 6** — Leave optional keys (altitude/heading/speed) blank or unavailable on desktop → they are simply absent from the entity (no attributes deleted, no error).
