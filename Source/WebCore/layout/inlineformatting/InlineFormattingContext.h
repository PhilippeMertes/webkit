/*
 * Copyright (C) 2018 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#pragma once

#if ENABLE(LAYOUT_FORMATTING_CONTEXT)

#include "DisplayBox.h"
#include "FormattingContext.h"
#include "InlineFormattingState.h"
#include "InlineLine.h"
#include <wtf/IsoMalloc.h>

namespace WebCore {
namespace Layout {

class FloatingState;
class InlineContainer;

// This class implements the layout logic for inline formatting contexts.
// https://www.w3.org/TR/CSS22/visuren.html#inline-formatting
class InlineFormattingContext : public FormattingContext {
    WTF_MAKE_ISO_ALLOCATED(InlineFormattingContext);
public:
    InlineFormattingContext(const Box& formattingContextRoot, InlineFormattingState&);
    void layout() const override;

private:
    void computeIntrinsicWidthConstraints() const override;

    class LineLayout {
    public:
        LineLayout(const InlineFormattingContext&);
        void layout(LayoutUnit widthConstraint) const;
        LayoutUnit computedIntrinsicWidth(LayoutUnit widthConstraint) const;

    private:
        LayoutState& layoutState() const { return m_formattingContext.layoutState(); }

        struct LineContent {
            Optional<unsigned> lastInlineItemIndex;
            std::unique_ptr<Line::Content> runs;
        };

        struct LineInput {
            LineInput(LayoutUnit logicalTop, LayoutUnit availableLogicalWidth, unsigned firstInlineItemIndex, const InlineItems&);

            LayoutUnit logicalTop;
            LayoutUnit availableLogicalWidth;
            unsigned firstInlineItemIndex { 0 };
            const InlineItems& inlineItems;
        };
        LineContent placeInlineItems(const LineInput&) const;
        void createDisplayRuns(const Line::Content&, LayoutUnit widthConstraint) const;
        void commitInlineItemToLine(Line&, const InlineItem&) const;
        void handleFloat(Line&, const FloatingContext&, const InlineItem& floatBox) const;
        void alignRuns(TextAlignMode, unsigned firstRunIndex, LayoutUnit availableWidth) const;

    private:
        static void justifyRuns(Line&);

    private:
        const InlineFormattingContext& m_formattingContext;
        InlineFormattingState& m_formattingState;
        FloatingState& m_floatingState;
        const Container& m_formattingRoot;
    };

    class Geometry : public FormattingContext::Geometry {
    public:
        static HeightAndMargin inlineBlockHeightAndMargin(const LayoutState&, const Box&);
        static WidthAndMargin inlineBlockWidthAndMargin(LayoutState&, const Box&, UsedHorizontalValues);
    };

    void layoutFormattingContextRoot(const Box&, UsedHorizontalValues) const;
    void computeIntrinsicWidthForFloatBox(const Box&) const;
    void computeMarginBorderAndPaddingForInlineContainer(const InlineContainer&, UsedHorizontalValues) const;
    void initializeMarginBorderAndPaddingForGenericInlineBox(const InlineBox&) const;
    void computeIntrinsicWidthForInlineBlock(const Box&) const;
    void computeWidthAndHeightForReplacedInlineBox(const Box&, UsedHorizontalValues) const;
    void computeHorizontalMargin(const Box&, UsedHorizontalValues) const;
    void computeHeightAndMargin(const Box&) const;
    void computeWidthAndMargin(const Box&, UsedHorizontalValues) const;

    void collectInlineContent() const;

    InlineFormattingState& formattingState() const { return downcast<InlineFormattingState>(FormattingContext::formattingState()); }
};

}
}
#endif
