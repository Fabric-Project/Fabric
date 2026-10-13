//
//  EditCommit.swift
//  Fabric
//

import Foundation

/// When a change made through a control becomes an undo step: a parameter's
/// value (ParameterObservableModel) or a node's settings (NodeSettingsDraft).
enum EditCommit
{
    /// Each change is a step of its own, as a picker, stepper or button makes
    /// them. A parameter control that reports an edit in progress, a drag or
    /// a text field, makes the edit one step, when it ends.
    case eachChange

    /// The changes are one step once they pause, and when editing ends: for
    /// text and code, and for a control that reports no end to an edit, such
    /// as a colour panel.
    case afterPause
}
