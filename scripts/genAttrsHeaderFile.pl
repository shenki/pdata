#!/usr/bin/env perl
# SPDX-License-Identifier: Apache-2.0

###############################################################
#                                                             #
# This tool will generate attributes meta data header file    #
# which will contain required attributes info to read/write   #
# from device tree file.                                      #
#                                                             #
###############################################################

use File::Basename;
use XML::LibXML;
use Getopt::Long;
use strict;

my $currDir = dirname($0);
my $topSrcDir = dirname($currDir);

require "$currDir/parseIntermediateXMLUtils.pl";

my $tool = basename($0);
# To store commandline arguments
my $inXMLFile;
my $attrsHeaderFileName;
my $filterAttrsFile;
my $attrsHeaderFileName;
my $help;
my $myVerbose;

my $outAttrsHeaderFN;
# To store xml data
my %attributeDefList;
# To store required targets and attributes
my %reqAttrsList;

# To use for header file handler
my $AIHeaderFH;
my $attrPrefix = "ATTR_";

# Process commandline options

GetOptions( "inXML:s"            => \$inXMLFile,
            "outAHFile:s"        => \$attrsHeaderFileName,
            "filterAttrsList:s"  => \$filterAttrsFile,
            "help"               => \$help,
            "verbose=s",         => \$myVerbose
          );


if ( $help )
{
    printUsage();
    exit 0;
}
if ( $inXMLFile eq "")
{
    print "--inXML is required with xml file which should contain all fapi and non-fapi attributes to generate header file\n";
    exit 1;
}
if ( $attrsHeaderFileName eq "" )
{
    print "--outAHFile is required with output header file name to store generated required attribute meta data\n";
    exit 1;
}
if ( ( $attrsHeaderFileName ne "") and !($attrsHeaderFileName =~ m/\.H/) )
{
    print "The given header file name \"$attrsHeaderFileName\" is not cpp header extension. So please use .H, because the generated header file used c++ feature\n";
    exit 1;
}

# Start fomr main function
main();

###############################
#      Subroutine Begin       #
###############################

sub printUsage
{
    print "
Description:

    *   This tool will generate attributes meta data header file which will contain
        required attributes info to read/write from device tree file.
        Note: This tool will expect MRW attributes definition format.\n" if $help;

    print "
Usage of $tool:

    -i|--inXML          : [M] :  Used to give xml name which is contains attributes
                                 information.
                                 Note: This tool will expect MRW attributes definition
                                 format.
                                 E.g.: --inXML <xml_file>

    -o|--outAHFile      : [M] :  Used to give output header file name
                                 E.g.: --outAHFile <attributes_info.H>

    -f|--filterAttrsList: [O] :  Used to give required attributes list in lsv file.
                                 E.g. : --filterAttrsList <systemName_FilterAttrsList.lsv>

    -v|--verbose        : [O] :  Use to print debug information
                                 To print different level of log use following format
                                 -v|--verbose A,C,E,W,I
                                 A - All, C - CRITICAL, E - ERROR, W - WARNING, I - INFO

    -h|--help           : [O] :  To print the tool usage

";
}

sub main
{
    initVerbose($myVerbose);

    %attributeDefList = getAttrsDef( $inXMLFile, $filterAttrsFile );

    createHeaderFile();
    print "\n$outAttrsHeaderFN is successfully created...\n";
}

sub createHeaderFile
{
    open $AIHeaderFH , '>', $attrsHeaderFileName or die "Could not open \"$attrsHeaderFileName\": \"$!\"";
    prepareHeaderFile();
    close $AIHeaderFH;
}

sub prepareHeaderFile
{
    prepareBeginningOfHeaderFile();
    prepareEndOfHeaderFile();
}

sub prepareBeginningOfHeaderFile
{
    my $repoName = substr($ENV{'PWD'}, rindex($ENV{'PWD'}, '/') + 1);

    $outAttrsHeaderFN = substr($attrsHeaderFileName, rindex($attrsHeaderFileName, "/") + 1);
    print {$AIHeaderFH} "// This file \'$outAttrsHeaderFN\' is auto generated by $repoName/$tool.\n// Please don't change\n\n";
    my $headerFileName = uc($outAttrsHeaderFN)."_";
    $headerFileName =~ s/\./_/g;
    print {$AIHeaderFH} "#ifndef $headerFileName\n";
    print {$AIHeaderFH} "#define $headerFileName\n";
    prepareReqHeaderFileInclude();
    prepareMacros();
    prepareAttrsMetaData();
    prepareAttrsTypeInfo();
}

sub prepareReqHeaderFileInclude
{
    print {$AIHeaderFH} "\n#include <string>\n";
    print {$AIHeaderFH} "\n#include \"dt_api.H\"\n";

    print {$AIHeaderFH} "\n";
}

sub prepareMacros
{
    # Prepare DT get and set macros and those can used to read/write
    # non fapi attribute and fapi attribute without fapi2 namespace in application
    prepareMacroToCallPdbgAPI();

    # Prepare Attributes GET and SET macros for FAPI attribute only due to namespace limitation
    print {$AIHeaderFH} "/* FAPI attributes macro list to get and set values in device tree.\n";
    print {$AIHeaderFH} "*  Macros are generated for each required fapi attributes, beacuse\n";
    print {$AIHeaderFH} "*  fapi layer expecting individual macro for each attribute\n";
    print {$AIHeaderFH} "*/\n";
    foreach my $attrID (sort (keys %attributeDefList) )
    {
        my $attributeDefinition = AttributeDefinition->new();
        $attributeDefinition = $attributeDefList{ $attrID };
        my $isFAPIAttr = @{$attributeDefinition->hwpfToAttrMap};
        if ( $isFAPIAttr <= 0)
        {
            next;
        }

        print {$AIHeaderFH} "\n/* $attrPrefix$attrID */\n";
        print {$AIHeaderFH} "#define $attrPrefix$attrID\_GETMACRO(ID, TARGET, VAL) getProperty(TARGET, #ID, &VAL, dtAttr::ID##_ElementCount, sizeof(VAL), dtAttr::ID##_TypeName, dtAttr::ID##_Spec)\n" if $attributeDefList{$attrID}->readable eq 1;
        print {$AIHeaderFH} "#define $attrPrefix$attrID\_SETMACRO(ID, TARGET, VAL) setProperty(TARGET, #ID, &VAL, dtAttr::ID##_ElementCount, sizeof(VAL), dtAttr::ID##_TypeName, dtAttr::ID##_Spec)\n" if $attributeDefList{$attrID}->writeable eq 1;
    }
    print {$AIHeaderFH} "\n";
}

sub prepareMacroToCallPdbgAPI
{
    # Should not use any namespace to get meta data but HWPs attributes tightly coupled with
    # fapi2 namespace, hence its fourced us to use namespace in macros as well to avoid pass
    # fapi2 namespace in application when using below macros
    print {$AIHeaderFH} "// This macro used to read both FAPI and Non-FAPI attribute values from device tree\n";
    print {$AIHeaderFH} "#define DT_GET_PROP(ID, TARGET, VAL) fapi2::getProperty(TARGET, #ID, &VAL, dtAttr::fapi2::ID##_ElementCount, sizeof(VAL), dtAttr::fapi2::ID##_TypeName, dtAttr::fapi2::ID##_Spec)\n\n";
    print {$AIHeaderFH} "// This macro used to write both FAPI and Non-FAPI attribute values into device tree\n";
    print {$AIHeaderFH} "#define DT_SET_PROP(ID, TARGET, VAL) fapi2::setProperty(TARGET, #ID, &VAL, dtAttr::fapi2::ID##_ElementCount, sizeof(VAL), dtAttr::fapi2::ID##_TypeName, dtAttr::fapi2::ID##_Spec)\n\n";
}

sub prepareEndOfHeaderFile
{
    print {$AIHeaderFH} "#endif\n";
}

sub prepareAttrsMetaData
{
    print {$AIHeaderFH} "/* All attributes meta data placed under fapi2 namespace, beacuse\n";
    print {$AIHeaderFH} "*  FAPI attributes passed with fapi2 namespace to get/set values\n";
    print {$AIHeaderFH} "*/\n";
    print {$AIHeaderFH} "\nnamespace dtAttr\n{\n"; # fapi2 namespace begin
    print {$AIHeaderFH} "\nnamespace fapi2\n{\n"; # fapi2 namespace begin

    foreach my $attrID (sort (keys %attributeDefList) )
    {
        my $attributeDefinition = AttributeDefinition->new();
        $attributeDefinition = $attributeDefList{ $attrID };
        if ( $attributeDefinition->datatype eq "simpleType" )
        {
            prepareSimpleTypeAttrMetaData($attrID, $attributeDefinition->simpleType);
        }
        elsif ( $attributeDefinition->datatype eq "complexType" )
        {
            prepareComplexTypeAttrMetaData($attrID, \@{$attributeDefinition->complexType->listOfComplexTypeFields}, $attributeDefinition->complexType->arrayDimension);
        }
        print {$AIHeaderFH} "\n";
    }

    print {$AIHeaderFH} "}\n\n"; # fapi2 namespace end
    print {$AIHeaderFH} "}\n\n"; # dtAttr namespace end
}

sub prepareSimpleTypeAttrMetaData
{
    my $attrID = $_[0];
    my $simpleObj = $_[1];

    my %ignoreSimpleSubType = ( "Target_t" => undef, "hbmutex" => undef, "hbrecursivemutex" => undef );

    if ( $simpleObj->DataType eq "array" )
    {
        my @dimList = split(',', $simpleObj->arrayDimension);
        my $totalEleCnt = 1;
        foreach my $dim ( @dimList )
        {
            $totalEleCnt *= $dim;
        }

        my $spec = $simpleObj->subType; $spec =~ s/\D//g; $spec /= 8;
        if ( $simpleObj->subType eq "string" )
        {
            # string storing as array of char
            $spec = 1;
            $totalEleCnt *= $simpleObj->stringSize;
        }

        prepareAllCommonReqMetaDataForAttr($attrID, $totalEleCnt, $spec, "array_", $simpleObj->subType);
    }
    elsif ( $simpleObj->DataType eq "enum" )
    {
        # Hardcoding element count as 1, because always will be one
        my $spec = $simpleObj->subType; $spec =~ s/\D//g; $spec /= 8;
        prepareAllCommonReqMetaDataForAttr($attrID, 1, $spec, "enum_", $simpleObj->subType);
    }
    elsif ( $simpleObj->DataType eq "string" )
    {
        prepareAllCommonReqMetaDataForAttr($attrID, $simpleObj->stringSize, 1, "", $simpleObj->DataType);
    }
    elsif ( !exists $ignoreSimpleSubType{$simpleObj->DataType} )
    {
        # Hardcoding element count as 1, because always will be one
        my $spec = $simpleObj->DataType; $spec =~ s/\D//g; $spec /= 8;
        prepareAllCommonReqMetaDataForAttr($attrID, 1, $spec, "", $simpleObj->DataType);
    }
}

sub prepareComplexTypeAttrMetaData
{
    my $attrID = $_[0];
    my @listOfComplexObj = @{$_[1]};
    my $arraySize = $_[2];
    $arraySize = 1 if $arraySize eq "";

    # Prepare Attribute struct name
    my @words = split('_', $attrID);
    my $structAttrName;
    foreach my $word (@words)
    {
        $structAttrName .= ucfirst ( lc($word) );
    }
    # Need to prepare spec for endianess to struct type
    # To make endiness for sturct type we need to do in memberwise
    my $structSpec;
    my $bitsCount = 0;
    foreach my $complexfield (@listOfComplexObj)
    {
        my $fieldType = $complexfield->type;
        if ( $complexfield->bits ne "" )
        {
            # Addeing each field bit field required bits count and then
            # If count is crossed 8 then making spec as one an reducing 8 and continuing
            $bitsCount += $complexfield->bits;
            if ( $bitsCount > 8)
            {
                $bitsCount -= 8;
                $structSpec .= 1;
            }
        }
        else
        {
            my $getNumericValFromType = $fieldType;
            $getNumericValFromType =~ s/\D//g;
            $structSpec .= $getNumericValFromType/8;
        }
    }

    # Adding spec as 1 if bit count is less than 8 after reading all fields
    if ( $bitsCount < 8 and $bitsCount != 0)
    {
        $structSpec .= 1;
    }
    elsif ( $bitsCount >= 8 )
    {
        # Adding spec as 1 continuously till reaching byte count into 0
        # (Byte count getting by dividing bit count by 8)
        my $byteCnt = $bitsCount / 8;
        while( $byteCnt > 0 ) { $structSpec .= 1; $byteCnt -= 1; }
    }

    prepareAllCommonReqMetaDataForAttr($attrID, $arraySize, $structSpec, "struct_", $structAttrName);
}

sub prepareAllCommonReqMetaDataForAttr
{
    my $attrID = $_[0];
    my $attrEleCount = $_[1];
    my $attrSpec = $_[2];
    my $attrTypePrefix = $_[3];
    my $attrType = $_[4];

    my $tmpTypeName = ( $attrTypePrefix eq "struct_" ) ? "struct" : $attrTypePrefix.$attrType;

    print {$AIHeaderFH} "\t/* $attrPrefix$attrID */\n";
    print {$AIHeaderFH} "\tconst std::string $attrPrefix$attrID\_TypeName = \"$tmpTypeName\";\n"; 
    print {$AIHeaderFH} "\tconst std::string $attrPrefix$attrID\_Spec = \"$attrSpec\";\n";
    print {$AIHeaderFH} "\tconst uint32_t $attrPrefix$attrID\_ElementCount = $attrEleCount;\n";
}

sub prepareAttrsTypeInfo
{
    print {$AIHeaderFH} "\t/* All Attributes datatype info with typedef by using attribute\n"; 
    print {$AIHeaderFH} "\t*  name and suffix as _Type, so that application can use.\n";
    print {$AIHeaderFH} "\t*/\n";
    print {$AIHeaderFH} "\t\n// To pack struct type attribute\n";
    print {$AIHeaderFH} "\t#define PACKED __attribute__((__packed__))\n\n";
    foreach my $attrID (sort (keys %attributeDefList) )
    {
        my $attributeDefinition = AttributeDefinition->new();
        $attributeDefinition = $attributeDefList{ $attrID };
        if ( $attributeDefinition->datatype eq "simpleType" )
        {
            prepareSimpleTypeAttrTypeInfo($attrID, $attributeDefinition->simpleType);
        }
        elsif ( $attributeDefinition->datatype eq "complexType" )
        {
            prepareComplexTypeAttrTypeInfo($attrID, \@{$attributeDefinition->complexType->listOfComplexTypeFields}, $attributeDefinition->complexType->arrayDimension);
        }

        print {$AIHeaderFH} "\n";
    }
}

sub prepareSimpleTypeAttrTypeInfo
{
    my $attrID = $_[0];
    my $simpleObj = $_[1];

    my %ignoreSimpleSubType = ( "Target_t" => undef, "hbmutex" => undef, "hbrecursivemutex" => undef );

    if ( $simpleObj->DataType eq "array" )
    {
        my @dimList = split(',', $simpleObj->arrayDimension);
        my $dimData;
        foreach my $dim ( @dimList )
        {
            $dimData .= "[".$dim."]";
        }
        
        if ( $simpleObj->subType eq "string" )
        {
            $dimData .= "[".$simpleObj->stringSize."]";
        }
        
        my $type = $simpleObj->subType;
        $type = "char" if $type eq "string";
        $type =~ s/enum_//g if $type =~ m/enum_/;
        print {$AIHeaderFH} "\ttypedef $type $attrPrefix$attrID\_Type$dimData;\n";
        if ($simpleObj->subType =~ m/enum_/)
        {
            print {$AIHeaderFH} "\tenum $attrPrefix$attrID\_Enum\n\t{\n";
            foreach my $enumpair ( @{$simpleObj->enumDefinition->enumeratorList})
            {
                print {$AIHeaderFH} "\t\tENUM_$attrPrefix$attrID\_$enumpair->[0] = $enumpair->[1],\n";
            }
            print {$AIHeaderFH} "\t};\n";
        }
    }
    elsif ( $simpleObj->DataType eq "enum" )
    {
        my $type = $simpleObj->subType;
        print {$AIHeaderFH} "\ttypedef $type $attrPrefix$attrID\_Type;\n";
        print {$AIHeaderFH} "\tenum $attrPrefix$attrID\_Enum\n\t{\n";
        foreach my $enumpair ( @{$simpleObj->enumDefinition->enumeratorList})
        {
            print {$AIHeaderFH} "\t\tENUM_$attrPrefix$attrID\_$enumpair->[0] = $enumpair->[1],\n";
        }
        print {$AIHeaderFH} "\t};\n";
    }
    elsif ( $simpleObj->DataType eq "string" )
    {
        my $dimData .= "[".$simpleObj->stringSize."]";
        print {$AIHeaderFH} "\ttypedef char $attrPrefix$attrID\_Type$dimData;\n";
    }
    elsif ( !exists $ignoreSimpleSubType{$simpleObj->DataType} )
    {
        my $type = $simpleObj->DataType;
        print {$AIHeaderFH} "\ttypedef $type $attrPrefix$attrID\_Type;\n";
    }
}

sub prepareComplexTypeAttrTypeInfo
{
    my $attrID = $_[0];
    my @listOfComplexObj = @{$_[1]};
    my $arraySize = $_[2];

    # Prepare Attribute struct name
    my @words = split('_', $attrID);
    my $structAttrName;
    foreach my $word (@words)
    {
        $structAttrName .= ucfirst ( lc($word) );
    }
    print {$AIHeaderFH} "\tstruct $structAttrName\n\t{\n";
   
    foreach my $complexfield (@listOfComplexObj)
    {
        my $fieldType = $complexfield->type;
        my $fieldName = $complexfield->name;
        my $fieldBits = "";
        if ( $complexfield->bits ne "" )
        {
            $fieldBits = " : ".$complexfield->bits;
        }
        print {$AIHeaderFH} "\t\t$fieldType $fieldName$fieldBits;\n\n";
    }
   
    print {$AIHeaderFH} "\t} PACKED;\n\n";
    my $dimData = "";
    $dimData = "[".$arraySize."]" if $arraySize ne "";

    print {$AIHeaderFH} "\ttypedef $structAttrName $attrPrefix$attrID\_Type$dimData;\n";
}
