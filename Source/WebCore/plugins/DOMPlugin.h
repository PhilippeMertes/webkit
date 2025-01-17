/*
    Copyright (C) 2008 Nokia Corporation and/or its subsidiary(-ies)

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Library General Public License for more details.

    You should have received a copy of the GNU Library General Public License
    along with this library; see the file COPYING.LIB.  If not, write to
    the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
    Boston, MA 02110-1301, USA.
*/

#pragma once

#include "FrameDestructionObserver.h"
#include "DOMMimeType.h"
#include "ScriptWrappable.h"
#include <wtf/RefCounted.h>
#include <wtf/RefPtr.h>

namespace WebCore {

class Plugin;
class PluginData;

class DOMPlugin final : public ScriptWrappable, public RefCounted<DOMPlugin>, public FrameDestructionObserver {
    WTF_MAKE_ISO_ALLOCATED(DOMPlugin);
public:
    static Ref<DOMPlugin> create(PluginData* pluginData, Frame* frame, PluginInfo pluginInfo) { return adoptRef(*new DOMPlugin(pluginData, frame, WTFMove(pluginInfo))); }
    ~DOMPlugin();

    String name() const;
    String filename() const;
    String description() const;

    unsigned length() const;

    RefPtr<DOMMimeType> item(unsigned index);
    RefPtr<DOMMimeType> namedItem(const AtomicString& propertyName);
    Vector<AtomicString> supportedPropertyNames();

private:
    DOMPlugin(PluginData*, Frame*, PluginInfo);
    RefPtr<PluginData> m_pluginData;
    PluginInfo m_pluginInfo;
};

} // namespace WebCore
