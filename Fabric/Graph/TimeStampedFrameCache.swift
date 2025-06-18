//
//  TimeStampedFrameCache.swift
//  v
//
//  Created by Anton Marini on 5/20/24.
//

import Foundation
import Metal

class TimeStampedFrameCache
{
    struct FrameTimeID : Hashable, Identifiable
    {
        let id:UUID
        let timeStamp:TimeInterval
        
        public func hash(into hasher: inout Hasher)
        {
            hasher.combine(self.id)
            hasher.combine(self.timeStamp)
        }
    }
    
    private var cache:[ FrameTimeID : (any MTLTexture)] = [:]
    
    func flushCache(forTime time:TimeInterval)
    {
        let keysToFlush = self.cache.keys.filter { $0.timeStamp < time }
        
        keysToFlush.forEach { self.cache.removeValue(forKey: $0) }
    }
    
    func cacheFrame(frame:(any MTLTexture), fromNode node:Node, atTime time:TimeInterval)
    {
        let frameID = FrameTimeID(id: node.id, timeStamp: time)
        
        self.cache[frameID] = frame
    }
    
    func cachedFrame(fromNode node:Node, atTime time:TimeInterval) -> (any MTLTexture)?
    {
        let frameID = FrameTimeID(id: node.id, timeStamp: time)

        return self.cache[frameID]
    }
    
}
