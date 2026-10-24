import type { WorkspaceEntity } from '../types'
import type { StepGroup, StepSubgroup } from '../lib/stepGroups'

interface StepGroupRailProps {
  entity: WorkspaceEntity
  groups: StepGroup[]
  activeGroup: string | null
  activeSubgroup: string | null
  onPickGroup: (group: StepGroup) => void
  onPickSubgroup: (group: StepGroup, subgroup: StepSubgroup) => void
}

const tabCount = (count: number) => `${count} tab${count === 1 ? '' : 's'}`

// One card per tab group, left of the report. The main card carries the card's
// own title; picking a card swaps the top bar over to that group's tabs. A group
// with subgroups opens to list them, and the top bar follows the subgroup.
export default function StepGroupRail({ entity, groups, activeGroup, activeSubgroup, onPickGroup, onPickSubgroup }: StepGroupRailProps) {
  const names = (indexes: number[]) => indexes.map(i => entity.steps[i].name).join('\n')
  return (
    <nav className="step-groups" aria-label="Tab groups">
      {groups.map(group => {
        const current = group.name === activeGroup
        const nested = group.subgroups.length > 0
        const name = group.name ?? entity.title
        return (
          <div key={group.name ?? ''} className="step-group-block">
            <button
              className={`step-group${current ? (nested ? ' open' : ' active') : ''}`}
              aria-pressed={current}
              aria-expanded={nested ? current : undefined}
              onClick={() => onPickGroup(group)}
              title={names(group.indexes)}
            >
              <span className="step-group-name">
                {nested && <span className="step-group-caret" aria-hidden="true">{current ? '▾' : '▸'}</span>}
                {name}
              </span>
              <span className="step-group-count">{tabCount(group.indexes.length)}</span>
            </button>
            {nested && current && (
              <div className="step-subgroups" role="group" aria-label={name}>
                {group.subgroups.map(sub => {
                  const open = sub.name === activeSubgroup
                  return (
                    <button
                      key={sub.name}
                      className={`step-group step-subgroup${open ? ' active' : ''}`}
                      aria-pressed={open}
                      onClick={() => onPickSubgroup(group, sub)}
                      title={names(sub.indexes)}
                    >
                      <span className="step-group-name">{sub.name}</span>
                      <span className="step-group-count">{tabCount(sub.indexes.length)}</span>
                    </button>
                  )
                })}
              </div>
            )}
          </div>
        )
      })}
    </nav>
  )
}
