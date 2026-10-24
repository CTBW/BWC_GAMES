import type { WorkspaceStep } from '../types'

// A card's tabs split by their optional `group`. Ungrouped tabs come first as the
// main group (name null); named groups follow in the order they first appear.
// A named group whose tabs set `subgroup` is split the same way, and its
// `indexes` then run subgroup by subgroup, the order the rail shows them in.

export interface StepSubgroup {
  name: string
  indexes: number[]
}

export interface StepGroup {
  name: string | null
  indexes: number[]
  subgroups: StepSubgroup[]
}

const OTHER = 'Other'

function bucket<K>(indexes: number[], key: (index: number) => K): Map<K, number[]> {
  const buckets = new Map<K, number[]>()
  for (const index of indexes) {
    const name = key(index)
    if (!buckets.has(name)) buckets.set(name, [])
    buckets.get(name)!.push(index)
  }
  return buckets
}

export function stepGroups(steps: WorkspaceStep[]): StepGroup[] {
  const all = steps.map((_, index) => index)
  const groups = bucket(all, i => steps[i].group?.trim() || null)
  const main = groups.get(null)
  // The main group always leads, even when a grouped tab comes first.
  const ordered = [...(main ? [[null, main] as const] : []), ...[...groups].filter(([name]) => name !== null)]
  return ordered.map(([name, indexes]) => {
    const named = name !== null && indexes.some(i => steps[i].subgroup?.trim())
    if (!named) return { name, indexes, subgroups: [] }
    const split = bucket(indexes, i => steps[i].subgroup?.trim() || OTHER)
    // Tabs without a subgroup close the list rather than sit between characters.
    const other = split.get(OTHER)
    split.delete(OTHER)
    if (other) split.set(OTHER, other)
    const subgroups = [...split].map(([sub, subIndexes]) => ({ name: sub, indexes: subIndexes }))
    return { name, indexes: subgroups.flatMap(sub => sub.indexes), subgroups }
  })
}
