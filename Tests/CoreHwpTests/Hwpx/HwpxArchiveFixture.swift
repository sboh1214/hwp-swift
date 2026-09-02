@testable import CoreHwp
import Foundation

/// `HwpFile` 종단 스위트가 공유하는 합성 HWPX 아카이브 조각.
///
/// 경로 해석(container.xml rootfile·manifest header item) 검증이 같은 구조를
/// 재사용하도록 클래스 밖으로 뺐다 — 헤더·구역 매퍼 스위트가
/// `HwpxHeaderFixture`/`HwpxSectionFixture`를 공유하는 것과 같은 관례이고,
/// 덕분에 종단 스위트가 `type_body_length` 상한 안에 머문다.
enum HwpxArchiveFixture {
    static let versionXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes" ?>\
    <hv:HCFVersion xmlns:hv="http://www.hancom.co.kr/hwpml/2011/version" \
    tagetApplication="WORDPROCESSOR" major="5" minor="1" micro="1" buildNumber="0"/>
    """
    static let manifestXML = """
    <opf:package xmlns:opf="http://www.idpf.org/2007/opf/">\
    <opf:manifest>\
    <opf:item id="header" href="Contents/header.xml" media-type="application/xml"/>\
    <opf:item id="section0" href="Contents/section0.xml" media-type="application/xml"/>\
    <opf:item id="image1" href="BinData/image1.png" media-type="image/png"/>\
    </opf:manifest>\
    <opf:spine><opf:itemref idref="header"/><opf:itemref idref="section0"/>\
    </opf:spine></opf:package>
    """
    static let headerXML = """
    <hh:head xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head" version="1.5" secCnt="1">\
    <hh:beginNum page="1" footnote="1" endnote="1" pic="1" tbl="1" equation="1"/>\
    <hh:refList>\
    <hh:fontfaces itemCnt="1"><hh:fontface lang="HANGUL" fontCnt="1">\
    <hh:font id="0" face="함초롬바탕" type="TTF" isEmbedded="0"/>\
    </hh:fontface></hh:fontfaces>\
    <hh:charProperties itemCnt="1">\
    <hh:charPr id="0" height="1000" textColor="#000000"/>\
    </hh:charProperties>\
    <hh:paraProperties itemCnt="1"><hh:paraPr id="0">\
    <hh:align horizontal="JUSTIFY"/></hh:paraPr></hh:paraProperties>\
    <hh:styles itemCnt="1">\
    <hh:style id="0" type="PARA" name="바탕글" engName="Normal" paraPrIDRef="0" \
    charPrIDRef="0" nextStyleIDRef="0"/></hh:styles>\
    </hh:refList></hh:head>
    """
    static let sectionXML = """
    <hs:sec xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section" \
    xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">\
    <hp:p id="1" paraPrIDRef="0" styleIDRef="0">\
    <hp:run charPrIDRef="0">\
    <hp:secPr id="" spaceColumns="1134" tabStop="8000">\
    <hp:pagePr landscape="WIDELY" width="59528" height="84186">\
    <hp:margin header="4252" footer="4252" gutter="0" left="8504" right="8504" \
    top="5668" bottom="4252"/></hp:pagePr></hp:secPr>\
    <hp:ctrl><hp:colPr id="" type="NEWSPAPER" layout="LEFT" colCount="1" \
    sameSz="1" sameGap="0"/></hp:ctrl>\
    </hp:run>\
    <hp:run charPrIDRef="0"><hp:t>HWPX 본문</hp:t></hp:run>\
    <hp:linesegarray><hp:lineseg textpos="0" vertpos="0" vertsize="1000" \
    textheight="1000" baseline="850" spacing="600" horzpos="0" horzsize="42520" \
    flags="393216"/></hp:linesegarray></hp:p></hs:sec>
    """
}
