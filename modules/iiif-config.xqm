
module namespace iiifc="https://e-editiones.org/api/iiif/config";

import module namespace iiif="https://e-editiones.org/api/iiif" at "iiif.xql";
import module namespace nav="http://www.tei-c.org/tei-simple/navigation" at "navigation.xql";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : Base URI of the IIIF image API service to use for the images.
 : Left empty — Grand Siecle images come as full URLs from various providers
 : (Gallica, etc.) via sourceDoc/surface/graphic/@url.
 : Set to a Cantaloupe/Loris URL if using a local image server with @facs prefix paths.
 :)
declare variable $iiifc:IMAGE_API_BASE := "";

(:~
 : URL prefix to use for the canvas id
 :)
declare variable $iiifc:CANVAS_ID_PREFIX := "https://e-editiones.org/canvas/";

(:~
 : Return all milestone elements pointing to images, usually pb or milestone.
 :
 : @param $doc the document root node to scan
 :)
declare function iiifc:milestones($doc as node()) as element()* {
    $doc//tei:pb
};

(:~
 : Extract the image URL from the milestone element.
 : Supports:
 :   - @facs with full URL or prefixed path (standard TEI Publisher)
 :   - @facs with fragment ID pointing to surface/graphic
 :   - @corresp pointing to sourceDoc/surface (Grand Siecle pipeline)
 : When the resolved URL is a full HTTP(S) URL (any IIIF provider), returns it as-is.
 : Otherwise applies the standard prefix-stripping (e.g. "iiif:path" -> "path")
 : for use with IMAGE_API_BASE.
 :)
declare function iiifc:milestone-id($milestone as element()) as xs:string? {
    let $facs := $milestone/@facs
    let $corresp := $milestone/@corresp
    let $link :=
        if ($facs) then
            if (starts-with($facs, "#")) then
                let $target := id(substring-after($facs, "#"), root($milestone))
                return
                    head($target/descendant-or-self::tei:graphic)/@url/string()
            else
                string($facs)
        else if ($corresp) then
            (: @corresp points to a surface in sourceDoc :)
            let $surface-id := substring-after($corresp, "#")
            let $surface := root($milestone)//tei:surface[@xml:id = $surface-id]
            return
                head($surface/tei:graphic)/@url/string()
        else
            ()
    return
        if (starts-with($link, "http")) then
            (: Full URL from any IIIF provider — return as-is :)
            $link
        else if ($link) then
            (: Relative/prefixed path — strip prefix before colon for use with IMAGE_API_BASE :)
            replace($link, "^[^:]+:(.*)", "$1")
        else
            ()
};

(:~
 : Provide general metadata fields for the object. The result will be merged into the
 : root of the presentation manifest.
 :)
declare function iiifc:metadata($doc as element(), $id as xs:string) as map(*) {
    map {
        "label": nav:get-metadata($doc, "title")/string(),
        "metadata": [
            map { "label": "Title", "value": nav:get-metadata($doc, "title")/string() },
            map { "label": "Creator", "value": nav:get-metadata($doc, "author")/string() },
            map { "label": "Language", "value": nav:get-metadata($doc, "language") },
            map { "label": "Date", "value": nav:get-metadata($doc, "date")/string() }
        ],
        "license": nav:get-metadata($doc, "license"),
        "rendering": [
            map {
                "@id": iiif:link("print/" || encode-for-uri($id)),
                "label": "Print preview",
                "format": "text/html"
            },
            map {
                "@id": iiif:link("api/document/" || encode-for-uri($id) || "/epub"),
                "label": "ePub",
                "format": "application/epub+zip"
            }
        ]
    }
};
