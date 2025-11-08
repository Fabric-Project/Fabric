//
//  Array-SafeGet.swift
//  v
//
//  Created by Anton Marini on 5/15/24.
//

import Foundation
extension Array 
{
    // Safely lookup an index that might be out of bounds,
    // returning nil if it does not exist
    func safeGet(index: Int) -> Element?
    {
        if 0 <= index && index < count 
        {
            return self[index]
        } 
        else
        {
            return nil
        }
    }
}

extension ContiguousArray
{
    // Safely lookup an index that might be out of bounds,
    // returning nil if it does not exist
    func safeGet(index: Int) -> Element?
    {
        if 0 <= index && index < count
        {
            return self[index]
        }
        else
        {
            return nil
        }
    }
}
