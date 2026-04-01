xquery version "3.1";

(:~
 : Custom API endpoints for the Grand Siècle project.
 : Linguistic search (lemma, POS) and language-filtered queries.
 :)
module namespace api="http://teipublisher.com/api/custom";

import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : Keep this. This function does the actual lookup in the imported modules.
 :)
declare function api:lookup($name as xs:string, $arity as xs:integer) {
    try {
        function-lookup(xs:QName($name), $arity)
    } catch * {
        ()
    }
};

(:~
 : Search by lemma across all documents, with optional language and document filters.
 : Returns word occurrences with their sentence context.
 :)
declare function api:lemma-search($request as map(*)) {
    let $query := $request?parameters?query
    let $lang := $request?parameters?lang
    let $doc := $request?parameters?doc
    let $start := ($request?parameters?start, 1)[1]
    let $per-page := ($request?parameters?per-page, 20)[1]
    let $collection := collection($config:data-default)
    let $scope := if ($doc) then
            $collection//tei:TEI[.//tei:idno[@type='internal'] = $doc]/tei:text
        else
            $collection//tei:TEI/tei:text
    (: Find matching <w> elements by lemma :)
    let $hits :=
        for $w in $scope//tei:w[@lemma]
        where if ($query) then matches($w/@lemma, $query, 'i') else true()
        where if ($lang) then $w/ancestor-or-self::*[@xml:lang][1]/@xml:lang = $lang else true()
        return $w
    let $total := count($hits)
    let $dummy := response:set-header("X-Total", string($total))
    return
        array {
            for $hit in subsequence($hits, $start, $per-page)
            let $doc-title := root($hit)//tei:titleStmt/tei:title[1]/string()
            let $file := util:document-name(root($hit))
            (: Get sentence context if available :)
            let $sentence := $hit/ancestor::tei:s[1]
            let $context := if ($sentence) then
                    normalize-space(string-join($sentence//text(), ''))
                else
                    let $parent := ($hit/ancestor::tei:ab, $hit/ancestor::tei:note, $hit/parent::*)[1]
                    return normalize-space(substring(string-join($parent//text(), ''), 1, 200))
            return map {
                "lemma": string($hit/@lemma),
                "form": string($hit),
                "pos": string($hit/@pos),
                "msd": string($hit/@msd),
                "norm": string(($hit/@norm, '')[1]),
                "lang": string(($hit/ancestor-or-self::*[@xml:lang][1]/@xml:lang, 'unknown')[1]),
                "context": $context,
                "document": $doc-title,
                "file": $file
            }
        }
};

(:~
 : POS concordance: list all words of a given POS category in a document.
 : Groups by lemma and counts occurrences.
 :)
declare function api:pos-concordance($request as map(*)) {
    let $pos := $request?parameters?pos
    let $doc := $request?parameters?doc
    let $lang := $request?parameters?lang
    let $collection := collection($config:data-default)
    let $scope := if ($doc) then
            $collection//tei:TEI[.//tei:idno[@type='internal'] = $doc]/tei:text
        else
            $collection//tei:TEI/tei:text
    let $words :=
        for $w in $scope//tei:w[@pos]
        where if ($pos) then $w/@pos = $pos else true()
        where if ($lang) then $w/ancestor-or-self::*[@xml:lang][1]/@xml:lang = $lang else true()
        return $w
    let $dummy := response:set-header("X-Total", string(count($words)))
    (: Group by lemma :)
    let $grouped :=
        for $w in $words
        group by $lemma := string($w/@lemma)
        let $forms := distinct-values($w/string())
        order by count($w) descending
        return map {
            "lemma": $lemma,
            "pos": string(head($w)/@pos),
            "count": count($w),
            "forms": array { $forms }
        }
    return
        array { $grouped }
};

(:~
 : List distinct POS tags found across documents, with counts.
 : Useful for populating filter dropdowns.
 :)
declare function api:pos-list($request as map(*)) {
    let $doc := $request?parameters?doc
    let $collection := collection($config:data-default)
    let $scope := if ($doc) then
            $collection//tei:TEI[.//tei:idno[@type='internal'] = $doc]/tei:text
        else
            $collection//tei:TEI/tei:text
    let $words := $scope//tei:w[@pos]
    let $grouped :=
        for $w in $words
        group by $pos := string($w/@pos)
        order by count($w) descending
        return map {
            "pos": $pos,
            "count": count($w)
        }
    return
        array { $grouped }
};
