import AppKit

extension SplitWatchers {
    func reconcileTopologyWhenReady() {
        let ticket = windows.mutationContext.capture()
        let ready = Set(displays.displays.map { $0.id.storageKey }) == ticket.topology.keys
            && displays.displays.allSatisfy { ticket.topology.contains($0) }
        guard !ready else { convergenceTask?.cancel(); convergenceTask = nil; convergenceID = nil; return }
        guard convergenceTask == nil else { return }
        let id = UUID()
        convergenceID = id
        convergenceTask = Task { [weak self] in
            await WindowMutationScope.$ticket.withValue(nil) {
                for delay in [100, 200, 400, 800, 1600, 2000] {
                    do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
                    guard let self, self.convergenceID == id else { return }
                    self.displays.refresh()
                    let snapshot = self.windows.mutationContext.capture()
                    if Set(self.displays.displays.map { $0.id.storageKey }) == snapshot.topology.keys,
                       self.displays.displays.allSatisfy({ snapshot.topology.contains($0) }) {
                        self.convergenceTask = nil
                        self.convergenceID = nil
                        self.contextsChanged(spaceNotification: false)
                        return
                    }
                }
                if self?.convergenceID == id {
                    self?.convergenceTask = nil
                    self?.convergenceID = nil
                    self?.lifecycleLog.notice("Display snapshots did not settle; stale placements remain paused")
                }
            }
        }
    }
}
